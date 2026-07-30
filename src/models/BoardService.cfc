component singleton {

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

		var columns = queryExecute(
			"SELECT CAST(id AS TEXT) AS id, name, position, wip_limit, color
			 FROM board_column
			 WHERE board_id = CAST(:boardId AS UUID) AND is_archived=false
			 ORDER BY position",
			{ boardId = selectedBoard.id },
			{ returntype = "array" }
		);
		var cards = queryExecute(
			"SELECT CAST(c.id AS TEXT) AS id, CAST(c.column_id AS TEXT) AS column_id,
			        c.title, c.description, c.priority, array_to_string(c.labels, ',') AS labels_csv, c.due_at, c.position,
			        c.version, c.created_at, u.display_name AS assignee_name,
			        COALESCE(att.attachment_count, 0) AS attachment_count,
			        COALESCE(att.attachment_names, '') AS attachment_names
			 FROM card c
			 LEFT JOIN app_user u ON u.id = c.assignee_id
			 LEFT JOIN LATERAL (
			     SELECT COUNT(*) AS attachment_count,
			            string_agg(a.original_filename, CHR(10) ORDER BY a.created_at) AS attachment_names
			     FROM attachment a
			     WHERE a.card_id = c.id AND a.status = 'available' AND a.deleted_at IS NULL
			 ) att ON true
			 WHERE c.board_id = CAST(:boardId AS UUID) AND c.archived_at IS NULL
			 ORDER BY c.column_id, c.position, c.created_at",
			{ boardId = selectedBoard.id },
			{ returntype = "array" }
		);

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
			   AND b.workspace_id = CAST(:workspaceId AS UUID)
			   AND wm.user_id = CAST(:userId AS UUID)",
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
		required string columnId
	){
		var rows = queryExecute(
			"SELECT CAST(c.column_id AS TEXT) AS from_column_id, CAST(c.board_id AS TEXT) AS board_id,
			        wm.role,target.wip_limit
			 FROM card c
			 JOIN workspace_member wm ON wm.workspace_id = c.workspace_id
			 JOIN board_column target ON target.id = CAST(:columnId AS UUID) AND target.board_id = c.board_id AND target.is_archived=false
			 WHERE c.id = CAST(:cardId AS UUID)
			   AND c.workspace_id = CAST(:workspaceId AS UUID)
			   AND wm.user_id = CAST(:userId AS UUID)
			   AND c.archived_at IS NULL",
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
		var targetWip=rows[1].wip_limit ?: "";
		if(toString(targetWip).len() && rows[1].from_column_id!=arguments.columnId){
			var targetCount=queryExecute(
				"SELECT COUNT(*) total FROM card WHERE column_id=CAST(:column AS UUID) AND archived_at IS NULL",
				{column=arguments.columnId},{returntype="array"}
			)[1].total;
			if(targetCount>=val(targetWip)) return {success=false,code="wip_limit"};
		}

		transaction {
			queryExecute(
				"UPDATE card
				 SET column_id = CAST(:columnId AS UUID),
				     position = (SELECT COALESCE(MAX(position), 0) + 1 FROM card WHERE column_id = CAST(:columnId AS UUID) AND archived_at IS NULL),
				     started_at = CASE WHEN started_at IS NULL THEN now() ELSE started_at END,
				     completed_at = CASE
				         WHEN (SELECT position FROM board_column WHERE id = CAST(:columnId AS UUID)) =
				              (SELECT MAX(position) FROM board_column WHERE board_id = CAST(:boardId AS UUID))
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
		}
		recordActivity( arguments.cardId, arguments.userId, "moved" );
		return { success = true };
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
			   AND access.user_id=CAST(:userId AS UUID) AND c.archived_at IS NULL",
			{ cardId=arguments.cardId, workspaceId=arguments.workspaceId, userId=arguments.userId },
			{ returntype="array" }
		);
		if ( !cards.len() ) return { found=false };
		return {
			found=true,
			card=cards[1],
			members=queryExecute(
				"SELECT CAST(u.id AS TEXT) id,u.display_name FROM workspace_member wm JOIN app_user u ON u.id=wm.user_id WHERE wm.workspace_id=CAST(:workspaceId AS UUID) ORDER BY u.display_name",
				{ workspaceId=arguments.workspaceId }, { returntype="array" }
			),
			comments=queryExecute(
				"SELECT cc.body,cc.created_at,COALESCE(u.display_name,'Former member') author_name FROM card_comment cc LEFT JOIN app_user u ON u.id=cc.author_id WHERE cc.card_id=CAST(:cardId AS UUID) ORDER BY cc.created_at",
				{ cardId=arguments.cardId }, { returntype="array" }
			),
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
