component singleton {

	struct function getDashboard(
		required string userId,
		required string workspaceId,
		struct requestedFilters = {}
	){
		var filters = normalizeFilters( arguments.requestedFilters );
		var params = {
			userId = arguments.userId,
			workspaceId = arguments.workspaceId
		};
		var predicates = [
			"c.workspace_id=CAST(:workspaceId AS UUID)",
			"c.assignee_id=CAST(:userId AS UUID)",
			"c.archived_at IS NULL",
			"b.is_archived=false",
			"bc.is_archived=false",
			"(bc.is_hidden_from_members=false OR current_member.role IN ('owner','admin'))",
			"(c.completed_at IS NULL OR c.completed_at>=now()-INTERVAL '7 days')"
		];

		if ( filters.query.len() ) {
			params.search = "%" & filters.query & "%";
			predicates.append(
				"(c.title ILIKE :search
				  OR COALESCE(c.description,'') ILIKE :search
				  OR array_to_string(c.labels, ',') ILIKE :search
				  OR b.name ILIKE :search
				  OR bc.name ILIKE :search)"
			);
		}
		if ( filters.boardId.len() ) {
			params.boardId = filters.boardId;
			predicates.append( "b.id=CAST(:boardId AS UUID)" );
		}
		if ( filters.priority.len() ) {
			params.priority = filters.priority;
			predicates.append( "c.priority=:priority" );
		}
		switch ( filters.due ) {
			case "overdue":
				predicates.append( "c.completed_at IS NULL AND CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)<CURRENT_DATE" );
				break;
			case "today":
				predicates.append( "c.completed_at IS NULL AND CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)=CURRENT_DATE" );
				break;
			case "upcoming":
				predicates.append( "c.completed_at IS NULL AND CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)>CURRENT_DATE" );
				break;
			case "no_due":
				predicates.append( "c.completed_at IS NULL AND c.due_at IS NULL" );
				break;
			case "completed":
				predicates.append( "c.completed_at IS NOT NULL" );
				break;
		}

		var orderBy = "c.due_at ASC NULLS LAST,
			CASE c.priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 ELSE 5 END,
			c.updated_at DESC";
		if ( filters.sort == "priority" ) {
			orderBy = "CASE c.priority WHEN 'urgent' THEN 1 WHEN 'high' THEN 2 WHEN 'medium' THEN 3 WHEN 'low' THEN 4 ELSE 5 END,
				c.due_at ASC NULLS LAST,c.updated_at DESC";
		} else if ( filters.sort == "updated" ) {
			orderBy = "c.updated_at DESC,c.due_at ASC NULLS LAST";
		}

		var cards = queryExecute(
			"SELECT CAST(c.id AS TEXT) AS id,CAST(c.board_id AS TEXT) AS board_id,
			        c.title,LEFT(COALESCE(c.description,''),360) AS description,
			        c.priority,array_to_string(c.labels, ',') AS labels_csv,
			        c.due_at,to_char(c.due_at AT TIME ZONE 'UTC','YYYY-MM-DD') AS due_date,
			        c.completed_at,c.updated_at,c.version,b.name AS board_name,bc.name AS column_name,bc.color AS column_color,
			        CASE
			          WHEN c.completed_at IS NOT NULL THEN 'completed'
			          WHEN c.due_at IS NULL THEN 'no_due'
			          WHEN CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)<CURRENT_DATE THEN 'overdue'
			          WHEN CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)=CURRENT_DATE THEN 'today'
			          ELSE 'upcoming'
			        END AS bucket
			 FROM card c
			 JOIN board b ON b.id=c.board_id AND b.workspace_id=c.workspace_id
			 JOIN board_column bc ON bc.id=c.column_id AND bc.board_id=c.board_id
			 JOIN workspace_member current_member
			   ON current_member.workspace_id=c.workspace_id
			  AND current_member.user_id=CAST(:userId AS UUID)
			 WHERE #arrayToList( predicates, ' AND ' )#
			 ORDER BY
			   CASE
			     WHEN c.completed_at IS NOT NULL THEN 5
			     WHEN c.due_at IS NULL THEN 4
			     WHEN CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)<CURRENT_DATE THEN 1
			     WHEN CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)=CURRENT_DATE THEN 2
			     ELSE 3
			   END,
			   #orderBy#",
			params,
			{ returntype="array" }
		);

		var groups = {
			overdue = [],
			today = [],
			upcoming = [],
			no_due = [],
			completed = []
		};
		for ( var card in cards ) {
			groups[ card.bucket ].append( card );
		}

		var summary = queryExecute(
			"SELECT
			    COUNT(*) AS total,
			    COUNT(*) FILTER (WHERE c.completed_at IS NULL AND CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)<CURRENT_DATE) AS overdue,
			    COUNT(*) FILTER (WHERE c.completed_at IS NULL AND CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)=CURRENT_DATE) AS today,
			    COUNT(*) FILTER (WHERE c.completed_at IS NULL AND CAST(c.due_at AT TIME ZONE 'UTC' AS DATE)>CURRENT_DATE) AS upcoming,
			    COUNT(*) FILTER (WHERE c.completed_at IS NULL AND c.due_at IS NULL) AS no_due,
			    COUNT(*) FILTER (WHERE c.completed_at IS NOT NULL) AS completed
			 FROM card c
			 JOIN board b ON b.id=c.board_id AND b.workspace_id=c.workspace_id AND b.is_archived=false
			 JOIN board_column bc ON bc.id=c.column_id AND bc.board_id=c.board_id AND bc.is_archived=false
			 JOIN workspace_member current_member
			   ON current_member.workspace_id=c.workspace_id
			  AND current_member.user_id=CAST(:userId AS UUID)
			 WHERE c.workspace_id=CAST(:workspaceId AS UUID)
			   AND c.assignee_id=CAST(:userId AS UUID)
			   AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR current_member.role IN ('owner','admin'))
			   AND (c.completed_at IS NULL OR c.completed_at>=now()-INTERVAL '7 days')",
			{ workspaceId=arguments.workspaceId, userId=arguments.userId },
			{ returntype="array" }
		)[ 1 ];

		var boards = queryExecute(
			"SELECT CAST(b.id AS TEXT) AS id,b.name,
			        (
			          SELECT COUNT(*)
			          FROM card assigned
			          JOIN board_column assigned_column
			            ON assigned_column.id=assigned.column_id
			           AND assigned_column.board_id=assigned.board_id
			           AND assigned_column.is_archived=false
			          WHERE assigned.board_id=b.id
			            AND assigned.workspace_id=b.workspace_id
			            AND assigned.assignee_id=CAST(:userId AS UUID)
			            AND assigned.archived_at IS NULL
			            AND (assigned_column.is_hidden_from_members=false OR current_member.role IN ('owner','admin'))
			            AND (assigned.completed_at IS NULL OR assigned.completed_at>=now()-INTERVAL '7 days')
			        ) AS assigned_count
			 FROM board b
			 JOIN workspace_member current_member
			   ON current_member.workspace_id=b.workspace_id
			  AND current_member.user_id=CAST(:userId AS UUID)
			 WHERE b.workspace_id=CAST(:workspaceId AS UUID) AND b.is_archived=false
			 ORDER BY b.position,b.created_at,b.name",
			{ workspaceId=arguments.workspaceId, userId=arguments.userId },
			{ returntype="array" }
		);

		return {
			cards = cards,
			groups = groups,
			summary = summary,
			boards = boards,
			filters = filters,
			hasFilters = filters.query.len() || filters.boardId.len() || filters.priority.len() || filters.due != "all" || filters.sort != "due"
		};
	}

	struct function getSavedFilters( required string userId, required string workspaceId ){
		var rows = queryExecute(
			"SELECT preference.search_query,
			        COALESCE(CAST(preference.board_id AS TEXT),'') AS saved_board_id,
			        COALESCE(CAST(active_board.id AS TEXT),'') AS board_id,
			        preference.priority_filter,preference.due_filter,preference.sort_order
			 FROM my_work_filter_preference preference
			 JOIN workspace_member membership
			   ON membership.workspace_id=preference.workspace_id
			  AND membership.user_id=preference.user_id
			 LEFT JOIN board active_board
			   ON active_board.id=preference.board_id
			  AND active_board.workspace_id=preference.workspace_id
			  AND active_board.is_archived=false
			 WHERE preference.workspace_id=CAST(:workspaceId AS UUID)
			   AND preference.user_id=CAST(:userId AS UUID)",
			{ workspaceId=arguments.workspaceId, userId=arguments.userId },
			{ returntype="array" }
		);
		if ( !rows.len() ) return normalizeFilters( {} );
		if ( rows[ 1 ].saved_board_id.len() && !rows[ 1 ].board_id.len() ) {
			queryExecute(
				"UPDATE my_work_filter_preference
				 SET board_id=NULL,updated_at=now()
				 WHERE workspace_id=CAST(:workspaceId AS UUID)
				   AND user_id=CAST(:userId AS UUID)
				   AND board_id=CAST(:boardId AS UUID)
				   AND NOT EXISTS(
				       SELECT 1
				       FROM board active_board
				       WHERE active_board.id=my_work_filter_preference.board_id
				         AND active_board.workspace_id=my_work_filter_preference.workspace_id
				         AND active_board.is_archived=false
				   )",
				{
					workspaceId=arguments.workspaceId,
					userId=arguments.userId,
					boardId=rows[ 1 ].saved_board_id
				}
			);
		}
		return normalizeFilters( {
			query=rows[ 1 ].search_query,
			boardId=rows[ 1 ].board_id,
			priority=rows[ 1 ].priority_filter,
			due=rows[ 1 ].due_filter,
			sort=rows[ 1 ].sort_order
		} );
	}

	struct function saveFilters(
		required string userId,
		required string workspaceId,
		required struct requestedFilters
	){
		var filters = normalizeFilters( arguments.requestedFilters );
		if ( filters.boardId.len() ) {
			var validBoard = queryExecute(
				"SELECT 1
				 FROM board
				 JOIN workspace_member membership
				   ON membership.workspace_id=board.workspace_id
				 WHERE board.id=CAST(:boardId AS UUID)
				   AND board.workspace_id=CAST(:workspaceId AS UUID)
				   AND board.is_archived=false
				   AND membership.user_id=CAST(:userId AS UUID)",
				{
					boardId=filters.boardId,
					workspaceId=arguments.workspaceId,
					userId=arguments.userId
				},
				{ returntype="array" }
			);
			if ( !validBoard.len() ) filters.boardId = "";
		}
		queryExecute(
			"INSERT INTO my_work_filter_preference(
			    workspace_id,user_id,search_query,board_id,priority_filter,due_filter,sort_order
			 )
			 SELECT membership.workspace_id,membership.user_id,:searchQuery,
			        CASE WHEN :boardId='' THEN NULL ELSE CAST(:boardId AS UUID) END,
			        :priorityFilter,:dueFilter,:sortOrder
			 FROM workspace_member membership
			 WHERE membership.workspace_id=CAST(:workspaceId AS UUID)
			   AND membership.user_id=CAST(:userId AS UUID)
			 ON CONFLICT(workspace_id,user_id) DO UPDATE
			 SET search_query=EXCLUDED.search_query,
			     board_id=EXCLUDED.board_id,
			     priority_filter=EXCLUDED.priority_filter,
			     due_filter=EXCLUDED.due_filter,
			     sort_order=EXCLUDED.sort_order,
			     updated_at=now()",
			{
				searchQuery=filters.query,
				boardId=filters.boardId,
				priorityFilter=filters.priority,
				dueFilter=filters.due,
				sortOrder=filters.sort,
				workspaceId=arguments.workspaceId,
				userId=arguments.userId
			}
		);
		return filters;
	}

	struct function updateCardFocus(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string priority,
		string dueDate = "",
		numeric version = 0
	){
		var cleanPriority = lCase( trim( arguments.priority ) );
		if ( !listFindNoCase( "none,low,medium,high,urgent", cleanPriority ) ) {
			return { success=false, code="invalid" };
		}
		var outcome = { success=false, code="forbidden" };
		transaction {
			var access = queryExecute(
				"SELECT wm.role,c.version
				 FROM card c
				 JOIN board b ON b.id=c.board_id AND b.workspace_id=c.workspace_id AND b.is_archived=false
				 JOIN board_column bc ON bc.id=c.column_id AND bc.board_id=c.board_id AND bc.is_archived=false
				 JOIN workspace_member wm ON wm.workspace_id=c.workspace_id
				 WHERE c.id=CAST(:cardId AS UUID)
				   AND c.workspace_id=CAST(:workspaceId AS UUID)
				   AND c.assignee_id=CAST(:userId AS UUID)
				   AND c.archived_at IS NULL
				   AND wm.user_id=CAST(:userId AS UUID)
				   AND (bc.is_hidden_from_members=false OR wm.role IN ('owner','admin'))
				 FOR UPDATE OF c",
				{ cardId=arguments.cardId, workspaceId=arguments.workspaceId, userId=arguments.userId },
				{ returntype="array" }
			);
			if ( access.len() && access[ 1 ].role == "viewer" ) {
				outcome = { success=false, code="read_only" };
			} else if ( access.len() && val( access[ 1 ].version ) != val( arguments.version ) ) {
				outcome = { success=false, code="conflict" };
			} else if ( access.len() ) {
				queryExecute(
					"UPDATE card
					 SET priority=:priority,
					     due_at=CASE WHEN :dueDate='' THEN NULL ELSE CAST(:dueDate AS DATE) END,
					     version=version+1,
					     updated_at=now()
					 WHERE id=CAST(:cardId AS UUID)",
					{
						priority=cleanPriority,
						dueDate=trim( arguments.dueDate ),
						cardId=arguments.cardId
					}
				);
				queryExecute(
					"INSERT INTO card_activity(card_id,actor_id,action)
					 VALUES(CAST(:cardId AS UUID),CAST(:userId AS UUID),'updated')",
					{ cardId=arguments.cardId, userId=arguments.userId }
				);
				outcome = { success=true };
			}
		}
		return outcome;
	}

	private struct function normalizeFilters( required struct requestedFilters ){
		var due = lCase( trim( arguments.requestedFilters.due ?: "all" ) );
		if ( !listFindNoCase( "all,overdue,today,upcoming,no_due,completed", due ) ) due = "all";
		var priority = lCase( trim( arguments.requestedFilters.priority ?: "" ) );
		if ( priority.len() && !listFindNoCase( "none,low,medium,high,urgent", priority ) ) priority = "";
		var sort = lCase( trim( arguments.requestedFilters.sort ?: "due" ) );
		if ( !listFindNoCase( "due,priority,updated", sort ) ) sort = "due";
		var boardId = trim( arguments.requestedFilters.boardId ?: "" );
		if ( boardId.len() && !reFindNoCase( "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", boardId ) ) boardId = "";
		return {
			query = left( trim( arguments.requestedFilters.query ?: "" ), 100 ),
			boardId = boardId,
			priority = priority,
			due = due,
			sort = sort
		};
	}

}
