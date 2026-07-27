component singleton {

	struct function getWorkspaceBoard( required string userId, required string workspaceId ){
		var boards = queryExecute(
			"SELECT CAST(b.id AS TEXT) AS id, b.name, b.description, w.name AS workspace_name, w.plan, wm.role
			 FROM board b
			 JOIN workspace w ON w.id = b.workspace_id
			 JOIN workspace_member wm ON wm.workspace_id = w.id
			 WHERE wm.user_id = CAST(:userId AS UUID)
			   AND w.id = CAST(:workspaceId AS UUID)
			   AND b.is_archived = false
			 ORDER BY b.created_at
			 LIMIT 1",
			{ userId = arguments.userId, workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
		if ( !boards.len() ) {
			return { found = false };
		}

		var columns = queryExecute(
			"SELECT CAST(id AS TEXT) AS id, name, position, wip_limit
			 FROM board_column
			 WHERE board_id = CAST(:boardId AS UUID)
			 ORDER BY position",
			{ boardId = boards[ 1 ].id },
			{ returntype = "array" }
		);
		var cards = queryExecute(
			"SELECT CAST(id AS TEXT) AS id, CAST(column_id AS TEXT) AS column_id, title, description, position, version, created_at
			 FROM card
			 WHERE board_id = CAST(:boardId AS UUID) AND archived_at IS NULL
			 ORDER BY column_id, position, created_at",
			{ boardId = boards[ 1 ].id },
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

		return { found = true, board = boards[ 1 ], columns = columns };
	}

	struct function createCard(
		required string userId,
		required string workspaceId,
		required string columnId,
		required string title,
		string description = ""
	){
		var access = queryExecute(
			"SELECT CAST(bc.board_id AS TEXT) AS board_id
			 FROM board_column bc
			 JOIN board b ON b.id = bc.board_id
			 JOIN workspace_member wm ON wm.workspace_id = b.workspace_id
			 WHERE bc.id = CAST(:columnId AS UUID)
			   AND b.workspace_id = CAST(:workspaceId AS UUID)
			   AND wm.user_id = CAST(:userId AS UUID)",
			{ columnId = arguments.columnId, workspaceId = arguments.workspaceId, userId = arguments.userId },
			{ returntype = "array" }
		);
		if ( !access.len() ) {
			return { success = false, code = "forbidden" };
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
		return { success = true, cardId = cardId };
	}

	struct function moveCard(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string columnId
	){
		var rows = queryExecute(
			"SELECT CAST(c.column_id AS TEXT) AS from_column_id, CAST(c.board_id AS TEXT) AS board_id
			 FROM card c
			 JOIN workspace_member wm ON wm.workspace_id = c.workspace_id
			 JOIN board_column target ON target.id = CAST(:columnId AS UUID) AND target.board_id = c.board_id
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
		return { success = true };
	}

}
