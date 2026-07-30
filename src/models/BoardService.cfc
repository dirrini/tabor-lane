component singleton {

	property name="avatarService" inject="AvatarService";

	struct function getWorkspaceBoard( required string userId, required string workspaceId, string boardId = "" ){
		var boards = queryExecute(
			"SELECT CAST(b.id AS TEXT) AS id, b.name, b.description, w.name AS workspace_name, w.plan, wm.role
			 FROM board b
			 JOIN workspace w ON w.id = b.workspace_id
			 JOIN workspace_member wm ON wm.workspace_id = w.id
			 WHERE wm.user_id = CAST(:userId AS UUID)
			   AND w.id = CAST(:workspaceId AS UUID)
			   AND b.is_archived = false
			 ORDER BY b.position,b.created_at,b.name",
			{ userId = arguments.userId, workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
		if ( !boards.len() ) {
			return { found = false };
		}

		var requestedBoardId=urlDecode(arguments.boardId);
		var selectedBoard=boards[1];
		for(var candidate in boards){
			if(candidate.id==requestedBoardId){selectedBoard=candidate;break;}
		}
		var canViewHiddenLanes = listFindNoCase( "owner,admin", selectedBoard.role ) > 0;

		var columns = queryExecute(
			"SELECT CAST(bc.id AS TEXT) AS id, bc.name, bc.position, bc.wip_limit, bc.color,
			        bc.is_hidden_from_members,
			        COALESCE(preference.width_px, 280) AS width_px,
			        COALESCE(preference.is_collapsed, false) AS is_collapsed
			 FROM board_column bc
			 LEFT JOIN board_column_preference preference
			   ON preference.column_id = bc.id
			  AND preference.user_id = CAST(:userId AS UUID)
			 WHERE bc.board_id = CAST(:boardId AS UUID) AND bc.is_archived=false
			   AND (bc.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
			 ORDER BY bc.position",
			{
				boardId = selectedBoard.id,
				userId = arguments.userId,
				canViewHidden = canViewHiddenLanes
			},
			{ returntype = "array" }
		);
		var cards = queryExecute(
			"SELECT CAST(c.id AS TEXT) AS id, CAST(c.column_id AS TEXT) AS column_id,
			        c.title, c.description, c.priority, array_to_string(c.labels, ',') AS labels_csv, c.due_at, c.position,
			        c.version, c.created_at,CAST(u.id AS TEXT) AS assignee_id,
			        u.display_name AS assignee_name,CAST(assignee_avatar.id AS TEXT) AS assignee_avatar_id,
			        COALESCE(att.attachment_count, 0) AS attachment_count,
			        COALESCE(att.attachment_names, '') AS attachment_names
			 FROM card c
			 JOIN board_column card_column
			   ON card_column.id=c.column_id
			  AND card_column.board_id=c.board_id
			  AND card_column.is_archived=false
			 LEFT JOIN app_user u ON u.id = c.assignee_id
			 LEFT JOIN workspace_member assignee_membership
			   ON assignee_membership.user_id=u.id
			  AND assignee_membership.workspace_id=c.workspace_id
			 LEFT JOIN user_avatar assignee_avatar
			   ON assignee_avatar.user_id=u.id
			  AND assignee_avatar.status='available' AND assignee_avatar.deleted_at IS NULL
			  AND assignee_membership.user_id IS NOT NULL
			 LEFT JOIN LATERAL (
			     SELECT COUNT(*) AS attachment_count,
			            string_agg(a.original_filename, CHR(10) ORDER BY a.created_at) AS attachment_names
			     FROM attachment a
			     WHERE a.card_id = c.id AND a.status = 'available' AND a.deleted_at IS NULL
			 ) att ON true
			 WHERE c.board_id = CAST(:boardId AS UUID) AND c.archived_at IS NULL
			   AND (card_column.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
			 ORDER BY c.column_id, c.position, c.created_at",
			{ boardId = selectedBoard.id, canViewHidden = canViewHiddenLanes },
			{ returntype = "array" }
		);
		for ( var assignedCard in cards ) {
			assignedCard.assignee_initials = avatarService.initials( assignedCard.assignee_name ?: "" );
		}

		for ( var column in columns ) {
			column.cards = [];
			for ( var card in cards ) {
				if ( card.column_id == column.id ) {
					column.cards.append( card );
				}
			}
		}

		return { found = true, board = selectedBoard, boards = boards, columns = columns };
	}

	struct function createCard(
		required string userId,
		required string workspaceId,
		required string columnId,
		required string title,
		string description = ""
	){
		var access = queryExecute(
			"SELECT CAST(bc.board_id AS TEXT) AS board_id, wm.role
			 FROM board_column bc
			 JOIN board b ON b.id = bc.board_id
			 JOIN workspace_member wm ON wm.workspace_id = b.workspace_id
			 WHERE bc.id = CAST(:columnId AS UUID)
			   AND bc.is_archived=false
			   AND b.is_archived=false
			   AND b.workspace_id = CAST(:workspaceId AS UUID)
			   AND wm.user_id = CAST(:userId AS UUID)
			   AND (bc.is_hidden_from_members=false OR wm.role IN ('owner','admin'))",
			{ columnId = arguments.columnId, workspaceId = arguments.workspaceId, userId = arguments.userId },
			{ returntype = "array" }
		);
		if ( !access.len() ) {
			return { success = false, code = "forbidden" };
		}
		if ( access[ 1 ].role == "viewer" ) {
			return { success = false, code = "read_only" };
		}

		var cardId = lCase( createUUID() );
		queryExecute(
			"INSERT INTO card (id, workspace_id, board_id, column_id, title, description, position)
			 SELECT CAST(:cardId AS UUID), CAST(:workspaceId AS UUID), CAST(:boardId AS UUID),
			        CAST(:columnId AS UUID), :title, :description,
			        COALESCE(MAX(position), 0) + 1
			 FROM card
			 WHERE column_id = CAST(:columnId AS UUID) AND archived_at IS NULL",
			{
				cardId = cardId,
				workspaceId = arguments.workspaceId,
				boardId = access[ 1 ].board_id,
				columnId = arguments.columnId,
				title = trim( arguments.title ),
				description = trim( arguments.description )
			}
		);
		recordActivity( cardId, arguments.userId, "created" );
		return { success = true, cardId = cardId, boardId = access[ 1 ].board_id };
	}

	struct function moveCard(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string columnId,
		string beforeCardId = ""
	){
		var rows = queryExecute(
			"SELECT CAST(c.column_id AS TEXT) AS from_column_id, CAST(c.board_id AS TEXT) AS board_id,
			        wm.role,target.wip_limit
			 FROM card c
			 JOIN workspace_member wm ON wm.workspace_id = c.workspace_id
			 JOIN board_column source
			   ON source.id=c.column_id
			  AND source.board_id=c.board_id
			  AND source.is_archived=false
			 JOIN board_column target ON target.id = CAST(:columnId AS UUID) AND target.board_id = c.board_id AND target.is_archived=false
			 WHERE c.id = CAST(:cardId AS UUID)
			   AND c.workspace_id = CAST(:workspaceId AS UUID)
			   AND wm.user_id = CAST(:userId AS UUID)
			   AND c.archived_at IS NULL
			   AND (source.is_hidden_from_members=false OR wm.role IN ('owner','admin'))
			   AND (target.is_hidden_from_members=false OR wm.role IN ('owner','admin'))",
			{
				columnId = arguments.columnId,
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId,
				userId = arguments.userId
			},
			{ returntype = "array" }
		);
		if ( !rows.len() ) {
			return { success = false, code = "forbidden" };
		}
		if ( rows[ 1 ].role == "viewer" ) {
			return { success = false, code = "read_only" };
		}
		var cleanBeforeCardId = trim( arguments.beforeCardId );
		if ( cleanBeforeCardId.len() ) {
			var validBeforeCard = queryExecute(
				"SELECT 1
				 FROM card
				 WHERE id = CAST(:beforeCardId AS UUID)
				   AND id <> CAST(:cardId AS UUID)
				   AND board_id = CAST(:boardId AS UUID)
				   AND column_id = CAST(:columnId AS UUID)
				   AND archived_at IS NULL",
				{
					beforeCardId = cleanBeforeCardId,
					cardId = arguments.cardId,
					boardId = rows[ 1 ].board_id,
					columnId = arguments.columnId
				},
				{ returntype = "array" }
			);
			if ( !validBeforeCard.len() ) {
				return { success = false, code = "invalid_position" };
			}
		}
		var targetWip=rows[1].wip_limit ?: "";
		if(toString(targetWip).len() && rows[1].from_column_id!=arguments.columnId){
			var targetCount=queryExecute(
				"SELECT COUNT(*) total FROM card WHERE column_id=CAST(:column AS UUID) AND archived_at IS NULL",
				{column=arguments.columnId},{returntype="array"}
			)[1].total;
			if(targetCount>=val(targetWip)) return {success=false,code="wip_limit"};
		}

		var columnChanged = rows[ 1 ].from_column_id != arguments.columnId;
		transaction {
			queryExecute(
				"SELECT id
				 FROM card
				 WHERE board_id = CAST(:boardId AS UUID)
				   AND column_id IN (CAST(:fromColumnId AS UUID), CAST(:columnId AS UUID))
				   AND archived_at IS NULL
				 FOR UPDATE",
				{
					boardId = rows[ 1 ].board_id,
					fromColumnId = rows[ 1 ].from_column_id,
					columnId = arguments.columnId
				}
			);

			if ( columnChanged ) {
				queryExecute(
					"UPDATE card
					 SET column_id = CAST(:columnId AS UUID),
					     started_at = COALESCE(started_at, now()),
					     completed_at = CASE
					         WHEN (
					             SELECT is_hidden_from_members
					             FROM board_column
					             WHERE id = CAST(:columnId AS UUID)
					         )
					         THEN completed_at
					         WHEN (
					             SELECT position
					             FROM board_column
					             WHERE id = CAST(:columnId AS UUID)
					         ) = (
					             SELECT MAX(position)
					             FROM board_column
					             WHERE board_id = CAST(:boardId AS UUID)
					               AND is_archived=false
					               AND is_hidden_from_members=false
					         )
					         THEN now() ELSE NULL END,
					     version = version + 1,
					     updated_at = now()
					 WHERE id = CAST(:cardId AS UUID)",
					{
						columnId = arguments.columnId,
						boardId = rows[ 1 ].board_id,
						cardId = arguments.cardId
					}
				);
				queryExecute(
					"INSERT INTO card_transition (workspace_id, card_id, from_column_id, to_column_id, actor_user_id)
					 VALUES (CAST(:workspaceId AS UUID), CAST(:cardId AS UUID), CAST(:fromColumnId AS UUID),
					         CAST(:columnId AS UUID), CAST(:userId AS UUID))",
					{
						workspaceId = arguments.workspaceId,
						cardId = arguments.cardId,
						fromColumnId = rows[ 1 ].from_column_id,
						columnId = arguments.columnId,
						userId = arguments.userId
					}
				);
			} else {
				queryExecute(
					"UPDATE card SET version=version+1,updated_at=now() WHERE id=CAST(:cardId AS UUID)",
					{ cardId=arguments.cardId }
				);
			}

			var targetCards = queryExecute(
				"SELECT CAST(id AS TEXT) AS id
				 FROM card
				 WHERE column_id=CAST(:columnId AS UUID)
				   AND archived_at IS NULL
				   AND id<>CAST(:cardId AS UUID)
				 ORDER BY position,created_at,id",
				{ columnId=arguments.columnId, cardId=arguments.cardId },
				{ returntype="array" }
			);
			var targetCardIds = [];
			for ( var targetCard in targetCards ) {
				targetCardIds.append( targetCard.id );
			}
			var inserted = false;
			if ( cleanBeforeCardId.len() ) {
				for ( var targetIndex=1; targetIndex<=targetCardIds.len(); targetIndex++ ) {
					if ( targetCardIds[ targetIndex ] == cleanBeforeCardId ) {
						targetCardIds.insertAt( targetIndex, arguments.cardId );
						inserted = true;
						break;
					}
				}
			}
			if ( !inserted ) {
				targetCardIds.append( arguments.cardId );
			}
			for ( var positionIndex=1; positionIndex<=targetCardIds.len(); positionIndex++ ) {
				queryExecute(
					"UPDATE card SET position=CAST(:position AS NUMERIC) WHERE id=CAST(:cardId AS UUID)",
					{ position=positionIndex, cardId=targetCardIds[ positionIndex ] }
				);
			}

			if ( columnChanged ) {
				var sourceCards = queryExecute(
					"SELECT CAST(id AS TEXT) AS id
					 FROM card
					 WHERE column_id=CAST(:columnId AS UUID) AND archived_at IS NULL
					 ORDER BY position,created_at,id",
					{ columnId=rows[ 1 ].from_column_id },
					{ returntype="array" }
				);
				for ( var sourceIndex=1; sourceIndex<=sourceCards.len(); sourceIndex++ ) {
					queryExecute(
						"UPDATE card SET position=CAST(:position AS NUMERIC) WHERE id=CAST(:cardId AS UUID)",
						{ position=sourceIndex, cardId=sourceCards[ sourceIndex ].id }
					);
				}
			}
		}
		recordActivity( arguments.cardId, arguments.userId, columnChanged ? "moved" : "reordered" );
		return { success = true };
	}

	struct function saveLanePreference(
		required string userId,
		required string workspaceId,
		required string columnId,
		required numeric widthPx,
		required boolean isCollapsed
	){
		var access = queryExecute(
			"SELECT 1
			 FROM board_column bc
			 JOIN board b ON b.id=bc.board_id AND b.is_archived=false
			 JOIN workspace_member wm ON wm.workspace_id=b.workspace_id
			 WHERE bc.id=CAST(:columnId AS UUID)
			   AND bc.is_archived=false
			   AND b.workspace_id=CAST(:workspaceId AS UUID)
			   AND wm.user_id=CAST(:userId AS UUID)
			   AND (bc.is_hidden_from_members=false OR wm.role IN ('owner','admin'))",
			{ columnId=arguments.columnId, workspaceId=arguments.workspaceId, userId=arguments.userId },
			{ returntype="array" }
		);
		if ( !access.len() ) return { success=false, code="forbidden" };

		var safeWidth = max( 240, min( 1200, round( arguments.widthPx ) ) );
		queryExecute(
			"INSERT INTO board_column_preference(user_id,column_id,width_px,is_collapsed)
			 VALUES(CAST(:userId AS UUID),CAST(:columnId AS UUID),CAST(:widthPx AS INTEGER),CAST(:isCollapsed AS BOOLEAN))
			 ON CONFLICT(user_id,column_id) DO UPDATE
			 SET width_px=EXCLUDED.width_px,is_collapsed=EXCLUDED.is_collapsed,updated_at=now()",
			{
				userId=arguments.userId,
				columnId=arguments.columnId,
				widthPx=safeWidth,
				isCollapsed=arguments.isCollapsed
			}
		);
		return { success=true, widthPx=safeWidth, isCollapsed=arguments.isCollapsed };
	}

	struct function getCardDetails( required string userId, required string workspaceId, required string cardId ){
		var cards = queryExecute(
			"SELECT CAST(c.id AS TEXT) id, c.title, c.description, c.priority, array_to_string(c.labels, ',') AS labels_csv,
			        to_char(c.due_at AT TIME ZONE 'UTC','YYYY-MM-DD') due_date,
			        CAST(c.assignee_id AS TEXT) assignee_id, c.created_at, c.updated_at,
			        CAST(b.id AS TEXT) board_id,b.name board_name, bc.name column_name, access.role AS access_role
			 FROM card c JOIN board b ON b.id=c.board_id JOIN board_column bc ON bc.id=c.column_id
			 JOIN workspace_member access ON access.workspace_id=c.workspace_id
			 WHERE c.id=CAST(:cardId AS UUID) AND c.workspace_id=CAST(:workspaceId AS UUID)
			   AND access.user_id=CAST(:userId AS UUID) AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))",
			{ cardId=arguments.cardId, workspaceId=arguments.workspaceId, userId=arguments.userId },
			{ returntype="array" }
		);
		if ( !cards.len() ) return { found=false };
		var members = queryExecute(
			"SELECT CAST(u.id AS TEXT) id,u.display_name
			 FROM workspace_member wm
			 JOIN app_user u ON u.id=wm.user_id
			 WHERE wm.workspace_id=CAST(:workspaceId AS UUID)
			 ORDER BY u.display_name",
			{ workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		var comments = queryExecute(
			"SELECT cc.body,cc.created_at,CAST(u.id AS TEXT) AS author_id,
			        COALESCE(u.display_name,'Former member') author_name,
			        CAST(author_avatar.id AS TEXT) AS author_avatar_id
			 FROM card_comment cc
			 LEFT JOIN app_user u ON u.id=cc.author_id
			 LEFT JOIN workspace_member author_membership
			   ON author_membership.user_id=u.id
			  AND author_membership.workspace_id=CAST(:workspaceId AS UUID)
			 LEFT JOIN user_avatar author_avatar
			   ON author_avatar.user_id=u.id
			  AND author_avatar.status='available' AND author_avatar.deleted_at IS NULL
			  AND author_membership.user_id IS NOT NULL
			 WHERE cc.card_id=CAST(:cardId AS UUID)
			 ORDER BY cc.created_at",
			{ cardId=arguments.cardId, workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		for ( var comment in comments ) {
			comment.author_initials = avatarService.initials( comment.author_name );
		}
		return {
			found=true,
			card=cards[1],
			members=members,
			comments=comments,
			activity=queryExecute(
				"SELECT ca.action,ca.created_at,COALESCE(u.display_name,'System') actor_name FROM card_activity ca LEFT JOIN app_user u ON u.id=ca.actor_id WHERE ca.card_id=CAST(:cardId AS UUID) ORDER BY ca.created_at DESC LIMIT 50",
				{ cardId=arguments.cardId }, { returntype="array" }
			)
		};
	}

	struct function updateCard( required string userId, required string workspaceId, required string cardId, required struct data ){
		var access=getCardDetails(arguments.userId,arguments.workspaceId,arguments.cardId);
		if(!access.found) return {success=false};
		if ( access.card.access_role == "viewer" ) return { success=false, code="read_only" };
		var priority=listFindNoCase("none,low,medium,high,urgent",arguments.data.priority ?: "")?lCase(arguments.data.priority):"none";
		var assignee=trim(arguments.data.assigneeId ?: "");
		if ( assignee.len() ) {
			var validAssignee=queryExecute(
				"SELECT 1 FROM workspace_member WHERE workspace_id=CAST(:workspace AS UUID) AND user_id=CAST(:assignee AS UUID)",
				{workspace=arguments.workspaceId,assignee=assignee},{returntype="array"}
			);
			if(!validAssignee.len()) return {success=false,code="invalid_assignee"};
		}
		var labelList=listToArray(arguments.data.labels ?: "");
		var cleanLabels=[];
		for(var label in labelList){
			var cleanLabel=trim(label);
			if(cleanLabel.len() && !arrayFindNoCase(cleanLabels,cleanLabel)) cleanLabels.append(left(cleanLabel,40));
			if(cleanLabels.len() == 10) break;
		}
		queryExecute(
			"UPDATE card SET title=:title,description=:description,priority=:priority,
			 assignee_id=CASE WHEN :assignee='' THEN NULL ELSE CAST(:assignee AS UUID) END,
			 due_at=CASE WHEN :dueDate='' THEN NULL ELSE CAST(:dueDate AS DATE) END,
			 labels=string_to_array(:labels,','),version=version+1,updated_at=now()
			 WHERE id=CAST(:cardId AS UUID) AND workspace_id=CAST(:workspaceId AS UUID)",
			{title=trim(arguments.data.title),description=trim(arguments.data.description ?: ""),priority=priority,assignee=assignee,
			 dueDate=trim(arguments.data.dueDate ?: ""),labels=arrayToList(cleanLabels),cardId=arguments.cardId,workspaceId=arguments.workspaceId}
		);
		recordActivity(arguments.cardId,arguments.userId,"updated");
		return {success=true,boardId=access.card.board_id};
	}

	struct function addComment( required string userId, required string workspaceId, required string cardId, required string body ){
		var access=getCardDetails(arguments.userId,arguments.workspaceId,arguments.cardId);
		if(!access.found) return {success=false,code="forbidden"};
		if(access.card.access_role=="viewer") return {success=false,code="read_only"};
		if(!trim(arguments.body).len() || trim(arguments.body).len()>5000) return {success=false,code="invalid_comment"};
		queryExecute("INSERT INTO card_comment(card_id,author_id,body) VALUES(CAST(:card AS UUID),CAST(:user AS UUID),:body)",
			{card=arguments.cardId,user=arguments.userId,body=trim(arguments.body)});
		recordActivity(arguments.cardId,arguments.userId,"commented");
		return {success=true};
	}

	struct function archiveCard( required string userId, required string workspaceId, required string cardId ){
		var access=getCardDetails(arguments.userId,arguments.workspaceId,arguments.cardId);
		if(!access.found) return {success=false,code="forbidden"};
		if(access.card.access_role=="viewer") return {success=false,code="read_only"};
		recordActivity(arguments.cardId,arguments.userId,"archived");
		queryExecute("UPDATE card SET archived_at=now(),updated_at=now() WHERE id=CAST(:card AS UUID)",{card=arguments.cardId});
		return {success=true,boardId=access.card.board_id};
	}

	private void function recordActivity(required string cardId,required string userId,required string action){
		queryExecute("INSERT INTO card_activity(card_id,actor_id,action) VALUES(CAST(:card AS UUID),CAST(:user AS UUID),:action)",
			{card=arguments.cardId,user=arguments.userId,action=arguments.action});
	}

}
