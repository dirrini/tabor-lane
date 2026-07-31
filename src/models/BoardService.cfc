component singleton {

	property name="avatarService" inject="AvatarService";
	property name="eventPublisherService" inject="EventPublisherService";

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
			"SELECT CAST(bc.board_id AS TEXT) AS board_id,bc.name AS lane_name,wm.role
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

		var cardId = canonicalUuid( createUUID() );
		var normalizedTitle = trim( arguments.title );
		transaction {
			queryExecute(
				"WITH visible_lifecycle AS (
				     SELECT MIN(position) AS first_position,MAX(position) AS last_position
				     FROM board_column
				     WHERE board_id=CAST(:boardId AS UUID)
				       AND is_archived=false
				       AND is_hidden_from_members=false
				 )
				 INSERT INTO card (
				     id,workspace_id,board_id,column_id,title,description,position,started_at,completed_at
				 )
				 SELECT CAST(:cardId AS UUID),CAST(:workspaceId AS UUID),CAST(:boardId AS UUID),
				        CAST(:columnId AS UUID),:title,:description,
				        (
				            SELECT COALESCE(MAX(existing.position),0)+1
				            FROM card existing
				            WHERE existing.column_id=CAST(:columnId AS UUID)
				              AND existing.archived_at IS NULL
				        ),
				        CASE
				            WHEN target.is_hidden_from_members=false
				             AND target.position=visible_lifecycle.first_position
				            THEN NULL
				            ELSE now()
				        END,
				        CASE
				            WHEN target.is_hidden_from_members=false
				             AND target.position<>visible_lifecycle.first_position
				             AND target.position=visible_lifecycle.last_position
				            THEN now()
				            ELSE NULL
				        END
				 FROM board_column target
				 CROSS JOIN visible_lifecycle
				 WHERE target.id=CAST(:columnId AS UUID)
				   AND target.board_id=CAST(:boardId AS UUID)
				   AND target.is_archived=false",
				{
					cardId = cardId,
					workspaceId = arguments.workspaceId,
					boardId = access[ 1 ].board_id,
					columnId = arguments.columnId,
					title = normalizedTitle,
					description = trim( arguments.description )
				}
			);
			recordActivity( cardId, arguments.userId, "created" );
			var createdPayload = {};
			createdPayload[ "cardTitle" ] = normalizedTitle;
			createdPayload[ "boardId" ] = access[ 1 ].board_id;
			createdPayload[ "laneId" ] = arguments.columnId;
			createdPayload[ "laneName" ] = access[ 1 ].lane_name;
			eventPublisherService.publish(
				workspaceId = arguments.workspaceId,
				eventType = "card.created",
				aggregateType = "card",
				aggregateId = cardId,
				actorId = arguments.userId,
				recipientUserIds = [],
				payload = createdPayload,
				deduplicationKey = "card.created:#cardId#"
			);
		}
		return { success = true, cardId = cardId, boardId = access[ 1 ].board_id };
	}

	struct function moveCard(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string columnId,
		string beforeCardId = ""
	){
		var outcome = { success = false, code = "forbidden" };
		transaction {
			outcome = moveCardLocked(
				userId = arguments.userId,
				workspaceId = arguments.workspaceId,
				cardId = arguments.cardId,
				columnId = arguments.columnId,
				beforeCardId = arguments.beforeCardId
			);
		}
		return outcome;
	}

	private struct function moveCardLocked(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string columnId,
		string beforeCardId = ""
	){
		var cardHints = queryExecute(
			"SELECT CAST(board_id AS TEXT) AS board_id
			 FROM card
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardHints.len() ) {
			return { success = false, code = "forbidden" };
		}

		// Lock order: board mutex -> card/lanes -> ordered lane cards.
		// The board mutex serializes WIP checks and reorder writes.
		var boardLocks = queryExecute(
			"SELECT id
			 FROM board
			 WHERE id=CAST(:boardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			   AND is_archived=false
			 FOR UPDATE",
			{
				boardId = cardHints[ 1 ].board_id,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !boardLocks.len() ) {
			return { success = false, code = "forbidden" };
		}

		var rows = queryExecute(
			"SELECT CAST(c.column_id AS TEXT) AS from_column_id,source.name AS from_column_name,
			        CAST(c.board_id AS TEXT) AS board_id,c.title AS card_title,c.version,
			        COALESCE(CAST(c.assignee_id AS TEXT),'') AS assignee_id,
			        wm.role,target.wip_limit,target.name AS to_column_name
			 FROM card c
			 JOIN board b
			   ON b.id=c.board_id
			  AND b.workspace_id=c.workspace_id
			  AND b.is_archived=false
			 JOIN workspace_member wm ON wm.workspace_id = c.workspace_id
			 JOIN board_column source
			   ON source.id=c.column_id
			  AND source.board_id=c.board_id
			  AND source.is_archived=false
			 JOIN board_column target ON target.id = CAST(:columnId AS UUID) AND target.board_id = c.board_id AND target.is_archived=false
			 WHERE c.id = CAST(:cardId AS UUID)
			   AND c.workspace_id = CAST(:workspaceId AS UUID)
			   AND c.board_id = CAST(:boardId AS UUID)
			   AND wm.user_id = CAST(:userId AS UUID)
			   AND c.archived_at IS NULL
			   AND (source.is_hidden_from_members=false OR wm.role IN ('owner','admin'))
			   AND (target.is_hidden_from_members=false OR wm.role IN ('owner','admin'))
			 FOR UPDATE OF c,source,target
			 FOR SHARE OF wm",
			{
				columnId = arguments.columnId,
				cardId = arguments.cardId,
				boardId = cardHints[ 1 ].board_id,
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
				   AND archived_at IS NULL
				 FOR UPDATE",
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
		var moveEventType = columnChanged ? "card.moved" : "card.reordered";
		var moveRecipients = [];
		if (
			( rows[ 1 ].assignee_id ?: "" ).len()
			&& compareNoCase( rows[ 1 ].assignee_id, arguments.userId ) != 0
		) {
			moveRecipients.append( rows[ 1 ].assignee_id );
		}
		var eventVersion = val( rows[ 1 ].version ) + 1;
		queryExecute(
			"SELECT id
				 FROM card
				 WHERE board_id = CAST(:boardId AS UUID)
				   AND column_id IN (CAST(:fromColumnId AS UUID), CAST(:columnId AS UUID))
				   AND archived_at IS NULL
				 ORDER BY column_id,position,created_at,id
				 FOR UPDATE",
				{
					boardId = rows[ 1 ].board_id,
					fromColumnId = rows[ 1 ].from_column_id,
					columnId = arguments.columnId
				}
		);

			var versionRows = [];
			if ( columnChanged ) {
				versionRows = queryExecute(
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
					 WHERE id = CAST(:cardId AS UUID)
					 RETURNING version",
					{
						columnId = arguments.columnId,
						boardId = rows[ 1 ].board_id,
						cardId = arguments.cardId
					},
					{ returntype = "array" }
				);
				if ( versionRows.len() ) eventVersion = val( versionRows[ 1 ].version );
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
				versionRows = queryExecute(
					"UPDATE card
					 SET version=version+1,updated_at=now()
					 WHERE id=CAST(:cardId AS UUID)
					 RETURNING version",
					{ cardId=arguments.cardId },
					{ returntype="array" }
				);
				if ( versionRows.len() ) eventVersion = val( versionRows[ 1 ].version );
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

			recordActivity(
				arguments.cardId,
				arguments.userId,
				columnChanged ? "moved" : "reordered"
			);
			var movePayload = {};
			movePayload[ "cardTitle" ] = rows[ 1 ].card_title;
			movePayload[ "boardId" ] = rows[ 1 ].board_id;
			movePayload[ "fromLaneId" ] = rows[ 1 ].from_column_id;
			movePayload[ "fromLaneName" ] = rows[ 1 ].from_column_name;
			movePayload[ "toLaneId" ] = arguments.columnId;
			movePayload[ "toLaneName" ] = rows[ 1 ].to_column_name;
			movePayload[ "assigneeId" ] = rows[ 1 ].assignee_id;
			movePayload[ "beforeCardId" ] = cleanBeforeCardId;
		eventPublisherService.publish(
				workspaceId = arguments.workspaceId,
				eventType = moveEventType,
				aggregateType = "card",
				aggregateId = arguments.cardId,
				actorId = arguments.userId,
				recipientUserIds = moveRecipients,
				payload = movePayload,
				deduplicationKey = "#moveEventType#:#arguments.cardId#:#eventVersion#"
		);
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
			        CAST(c.assignee_id AS TEXT) assignee_id, c.created_at, c.updated_at,c.version,
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
		var outcome = { success = false };
		transaction {
			outcome = updateCardLocked(
				userId = arguments.userId,
				workspaceId = arguments.workspaceId,
				cardId = arguments.cardId,
				data = arguments.data
			);
		}
		return outcome;
	}

	private struct function updateCardLocked(
		required string userId,
		required string workspaceId,
		required string cardId,
		required struct data
	){
		var cardLockRows = queryExecute(
			"SELECT 1
			 FROM card
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			 FOR UPDATE",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardLockRows.len() ) return { success = false };

		var cardRows = queryExecute(
			"SELECT c.title,c.description,c.priority,
			        COALESCE(CAST(c.assignee_id AS TEXT),'') AS assignee_id,
			        c.version,CAST(c.board_id AS TEXT) AS board_id,
			        access.role AS access_role
			 FROM card c
			 JOIN board b
			   ON b.id=c.board_id
			  AND b.workspace_id=c.workspace_id
			  AND b.is_archived=false
			 JOIN board_column bc
			   ON bc.id=c.column_id
			  AND bc.board_id=c.board_id
			  AND bc.is_archived=false
			 JOIN workspace_member access
			   ON access.workspace_id=c.workspace_id
			  AND access.user_id=CAST(:userId AS UUID)
			 WHERE c.id=CAST(:cardId AS UUID)
			   AND c.workspace_id=CAST(:workspaceId AS UUID)
			   AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))
			 FOR UPDATE OF c
			 FOR SHARE OF access",
			{
				userId = arguments.userId,
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		var access = { found = cardRows.len() > 0 };
		if ( access.found ) access[ "card" ] = cardRows[ 1 ];
		if(!access.found) return {success=false};
		if ( access.card.access_role == "viewer" ) return { success=false, code="read_only" };
		var priority=listFindNoCase("none,low,medium,high,urgent",arguments.data.priority ?: "")?lCase(arguments.data.priority):"none";
		var assignee=trim(arguments.data.assigneeId ?: "");
		if ( assignee.len() ) {
			var validAssignee=queryExecute(
				"SELECT 1
				 FROM workspace_member
				 WHERE workspace_id=CAST(:workspace AS UUID)
				   AND user_id=CAST(:assignee AS UUID)
				 FOR SHARE",
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
		var normalizedTitle = trim( arguments.data.title );
		var normalizedDueDate = trim( arguments.data.dueDate ?: "" );
		var previousAssignee = trim( access.card.assignee_id ?: "" );
		var assignmentChanged = compareNoCase( previousAssignee, assignee ) != 0;
		var eventVersion = val( access.card.version ) + 1;
		var updateRows = queryExecute(
			"UPDATE card SET title=:title,description=:description,priority=:priority,
			 assignee_id=CASE WHEN :assignee='' THEN NULL ELSE CAST(:assignee AS UUID) END,
			 due_at=CASE WHEN :dueDate='' THEN NULL ELSE CAST(:dueDate AS DATE) END,
			 labels=string_to_array(:labels,','),version=version+1,updated_at=now()
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			   AND archived_at IS NULL
			 RETURNING version",
			{
				title=normalizedTitle,
				description=trim(arguments.data.description ?: ""),
				priority=priority,
				assignee=assignee,
				dueDate=normalizedDueDate,
				labels=arrayToList(cleanLabels),
				cardId=arguments.cardId,
				workspaceId=arguments.workspaceId
			},
			{ returntype="array" }
		);
		if ( !updateRows.len() ) return { success = false };
		eventVersion = val( updateRows[ 1 ].version );
		recordActivity( arguments.cardId, arguments.userId, "updated" );

		var updatedPayload = {};
		updatedPayload[ "cardTitle" ] = normalizedTitle;
		updatedPayload[ "boardId" ] = access.card.board_id;
		updatedPayload[ "priority" ] = priority;
		updatedPayload[ "assigneeId" ] = assignee;
		updatedPayload[ "dueDate" ] = normalizedDueDate;
		updatedPayload[ "labels" ] = cleanLabels;
		eventPublisherService.publish(
			workspaceId = arguments.workspaceId,
			eventType = "card.updated",
			aggregateType = "card",
			aggregateId = arguments.cardId,
			actorId = arguments.userId,
			recipientUserIds = [],
			payload = updatedPayload,
			deduplicationKey = "card.updated:#arguments.cardId#:#eventVersion#"
		);

		if ( assignmentChanged ) {
			var assignedRecipients = [];
			if ( assignee.len() ) assignedRecipients.append( assignee );
			var assignedPayload = {};
			assignedPayload[ "cardTitle" ] = normalizedTitle;
			assignedPayload[ "boardId" ] = access.card.board_id;
			assignedPayload[ "previousAssigneeId" ] = previousAssignee;
			assignedPayload[ "assigneeId" ] = assignee;
			eventPublisherService.publish(
				workspaceId = arguments.workspaceId,
				eventType = "card.assigned",
				aggregateType = "card",
				aggregateId = arguments.cardId,
				actorId = arguments.userId,
				recipientUserIds = assignedRecipients,
				payload = assignedPayload,
				deduplicationKey = "card.assigned:#arguments.cardId#:#eventVersion#"
			);
		}
		return {success=true,boardId=access.card.board_id};
	}

	struct function addComment( required string userId, required string workspaceId, required string cardId, required string body ){
		var outcome = { success = false, code = "forbidden" };
		transaction {
			outcome = addCommentLocked(
				userId = arguments.userId,
				workspaceId = arguments.workspaceId,
				cardId = arguments.cardId,
				body = arguments.body
			);
		}
		return outcome;
	}

	private struct function addCommentLocked(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string body
	){
		var normalizedBody = trim( arguments.body );
		if ( !normalizedBody.len() || normalizedBody.len() > 5000 ) {
			return { success = false, code = "invalid_comment" };
		}

		var cardLockRows = queryExecute(
			"SELECT 1
			 FROM card
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			 FOR UPDATE",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardLockRows.len() ) return { success = false, code = "forbidden" };

		var cardRows = queryExecute(
			"SELECT c.title,CAST(c.board_id AS TEXT) AS board_id,
			        COALESCE(CAST(c.assignee_id AS TEXT),'') AS assignee_id,
			        access.role AS access_role
			 FROM card c
			 JOIN board b
			   ON b.id=c.board_id
			  AND b.workspace_id=c.workspace_id
			  AND b.is_archived=false
			 JOIN board_column bc
			   ON bc.id=c.column_id
			  AND bc.board_id=c.board_id
			  AND bc.is_archived=false
			 JOIN workspace_member access
			   ON access.workspace_id=c.workspace_id
			  AND access.user_id=CAST(:userId AS UUID)
			 WHERE c.id=CAST(:cardId AS UUID)
			   AND c.workspace_id=CAST(:workspaceId AS UUID)
			   AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))
			 FOR UPDATE OF c
			 FOR SHARE OF access",
			{
				userId = arguments.userId,
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardRows.len() ) return { success = false, code = "forbidden" };
		var card = cardRows[ 1 ];
		if ( card.access_role == "viewer" ) return { success = false, code = "read_only" };

		var commentRecipients = [];
		if (
			card.assignee_id.len()
			&& compareNoCase( card.assignee_id, arguments.userId ) != 0
		) {
			commentRecipients.append( card.assignee_id );
		}

		var commentRows = queryExecute(
			"INSERT INTO card_comment(card_id,author_id,body)
			 VALUES(CAST(:card AS UUID),CAST(:user AS UUID),:body)
			 RETURNING CAST(id AS TEXT) AS id",
			{
				card=arguments.cardId,
				user=arguments.userId,
				body=normalizedBody
			},
			{ returntype="array" }
		);
		var commentId = commentRows[ 1 ].id;
		recordActivity( arguments.cardId, arguments.userId, "commented" );
		var commentedPayload = {};
		commentedPayload[ "cardTitle" ] = card.title;
		commentedPayload[ "boardId" ] = card.board_id;
		commentedPayload[ "commentId" ] = commentId;
		commentedPayload[ "commentBody" ] = normalizedBody;
		commentedPayload[ "assigneeId" ] = card.assignee_id;
		eventPublisherService.publish(
			workspaceId = arguments.workspaceId,
			eventType = "card.commented",
			aggregateType = "card",
			aggregateId = arguments.cardId,
			actorId = arguments.userId,
			recipientUserIds = commentRecipients,
			payload = commentedPayload,
			deduplicationKey = "card.commented:#commentId#"
		);
		return {success=true};
	}

	struct function archiveCard( required string userId, required string workspaceId, required string cardId ){
		var outcome = { success = false, code = "forbidden" };
		transaction {
			outcome = archiveCardLocked(
				userId = arguments.userId,
				workspaceId = arguments.workspaceId,
				cardId = arguments.cardId
			);
		}
		return outcome;
	}

	private struct function archiveCardLocked(
		required string userId,
		required string workspaceId,
		required string cardId
	){
		var cardLockRows = queryExecute(
			"SELECT 1
			 FROM card
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			 FOR UPDATE",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardLockRows.len() ) return { success = false, code = "forbidden" };

		var cardRows = queryExecute(
			"SELECT c.title,CAST(c.board_id AS TEXT) AS board_id,
			        access.role AS access_role
			 FROM card c
			 JOIN board b
			   ON b.id=c.board_id
			  AND b.workspace_id=c.workspace_id
			  AND b.is_archived=false
			 JOIN board_column bc
			   ON bc.id=c.column_id
			  AND bc.board_id=c.board_id
			  AND bc.is_archived=false
			 JOIN workspace_member access
			   ON access.workspace_id=c.workspace_id
			  AND access.user_id=CAST(:userId AS UUID)
			 WHERE c.id=CAST(:cardId AS UUID)
			   AND c.workspace_id=CAST(:workspaceId AS UUID)
			   AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))
			 FOR UPDATE OF c
			 FOR SHARE OF access",
			{
				userId = arguments.userId,
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardRows.len() ) return { success = false, code = "forbidden" };
		var card = cardRows[ 1 ];
		if ( card.access_role == "viewer" ) return { success = false, code = "read_only" };

		var archivedRows = queryExecute(
			"UPDATE card
			 SET archived_at=now(),updated_at=now()
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			   AND archived_at IS NULL
			 RETURNING 1",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !archivedRows.len() ) return { success = false, code = "forbidden" };

		recordActivity( arguments.cardId, arguments.userId, "archived" );
		var archivedPayload = {};
		archivedPayload[ "cardTitle" ] = card.title;
		archivedPayload[ "boardId" ] = card.board_id;
		eventPublisherService.publish(
			workspaceId = arguments.workspaceId,
			eventType = "card.archived",
			aggregateType = "card",
			aggregateId = arguments.cardId,
			actorId = arguments.userId,
			recipientUserIds = [],
			payload = archivedPayload,
			deduplicationKey = "card.archived:#arguments.cardId#"
		);
		return { success = true, boardId = card.board_id };
	}

	private void function recordActivity(required string cardId,required string userId,required string action){
		queryExecute("INSERT INTO card_activity(card_id,actor_id,action) VALUES(CAST(:card AS UUID),CAST(:user AS UUID),:action)",
			{card=arguments.cardId,user=arguments.userId,action=arguments.action});
	}

	private string function canonicalUuid( required string value ){
		var compact = lCase( replace( arguments.value, "-", "", "all" ) );
		if ( !reFind( "^[0-9a-f]{32}$", compact ) ) {
			throw(
				type = "Board.InvalidUuid",
				message = "Could not generate a valid card UUID."
			);
		}
		return left( compact, 8 )
			& "-" & mid( compact, 9, 4 )
			& "-" & mid( compact, 13, 4 )
			& "-" & mid( compact, 17, 4 )
			& "-" & right( compact, 12 );
	}

}
