component singleton {

	array function listBoards( required struct principal ){
		var rows = queryExecute(
			"SELECT CAST(board_record.id AS TEXT) AS id,
			        board_record.name,COALESCE(board_record.description,'') AS description,
			        board_record.position,
			        to_char(board_record.created_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS""Z""') AS created_at,
			        to_char(board_record.updated_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS""Z""') AS updated_at
			 FROM board board_record
			 JOIN workspace_member membership
			   ON membership.workspace_id=board_record.workspace_id
			  AND membership.user_id=CAST(:userId AS UUID)
			 WHERE board_record.workspace_id=CAST(:workspaceId AS UUID)
			   AND board_record.is_archived=false
			 ORDER BY board_record.position,board_record.created_at,board_record.id",
			{
				userId=arguments.principal.userId,
				workspaceId=arguments.principal.workspaceId
			},
			{ returntype="array" }
		);

		var boards = [];
		for ( var row in rows ) boards.append( boardDto( row ) );
		return boards;
	}

	struct function getBoard( required struct principal, required string boardId ){
		var rows = queryExecute(
			"SELECT CAST(board_record.id AS TEXT) AS id,
			        board_record.name,COALESCE(board_record.description,'') AS description,
			        board_record.position,
			        to_char(board_record.created_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS""Z""') AS created_at,
			        to_char(board_record.updated_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS""Z""') AS updated_at,
			        membership.role
			 FROM board board_record
			 JOIN workspace_member membership
			   ON membership.workspace_id=board_record.workspace_id
			  AND membership.user_id=CAST(:userId AS UUID)
			 WHERE board_record.id=CAST(:boardId AS UUID)
			   AND board_record.workspace_id=CAST(:workspaceId AS UUID)
			   AND board_record.is_archived=false",
			{
				userId=arguments.principal.userId,
				workspaceId=arguments.principal.workspaceId,
				boardId=arguments.boardId
			},
			{ returntype="array" }
		);
		if ( !rows.len() ) return { found=false };

		var lanes = queryExecute(
			"SELECT CAST(lane.id AS TEXT) AS id,lane.name,lane.position,
			        lane.wip_limit,COALESCE(lane.color,'') AS color,
			        lane.is_completion_lane
			 FROM board_column lane
			 WHERE lane.board_id=CAST(:boardId AS UUID)
			   AND lane.is_archived=false
			   AND (
			       lane.is_hidden_from_members=false
			       OR CAST(:canViewHidden AS BOOLEAN)
			   )
			 ORDER BY lane.position,lane.created_at,lane.id",
			{
				boardId=arguments.boardId,
				canViewHidden=listFindNoCase( "owner,admin", rows[ 1 ].role ) > 0
			},
			{ returntype="array" }
		);

		var result = boardDto( rows[ 1 ] );
		result[ "lanes" ] = [];
		for ( var lane in lanes ) result.lanes.append( laneDto( lane ) );
		return { found=true,board=result };
	}

	struct function listBoardCards(
		required struct principal,
		required string boardId
	){
		var boardAccess = getBoard( arguments.principal, arguments.boardId );
		if ( !boardAccess.found ) return { found=false };

		var rows = queryExecute(
			"SELECT CAST(card_record.id AS TEXT) AS id,
			        CAST(card_record.board_id AS TEXT) AS board_id,
			        CAST(card_record.column_id AS TEXT) AS lane_id,
			        card_record.title,COALESCE(card_record.description,'') AS description,
			        card_record.priority,
			        array_to_string(card_record.labels, ',') AS labels_csv,
			        card_record.position,card_record.version,
			        COALESCE(to_char(card_record.due_at AT TIME ZONE 'UTC',
			                         'YYYY-MM-DD""T""HH24:MI:SS""Z""'),'') AS due_at,
			        COALESCE(to_char(card_record.completed_at AT TIME ZONE 'UTC',
			                         'YYYY-MM-DD""T""HH24:MI:SS""Z""'),'') AS completed_at,
			        COALESCE(to_char(card_record.blocked_at AT TIME ZONE 'UTC',
			                         'YYYY-MM-DD""T""HH24:MI:SS""Z""'),'') AS blocked_at,
			        to_char(card_record.created_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS""Z""') AS created_at,
			        to_char(card_record.updated_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS""Z""') AS updated_at
			 FROM card card_record
			 JOIN board board_record
			   ON board_record.id=card_record.board_id
			  AND board_record.workspace_id=card_record.workspace_id
			  AND board_record.is_archived=false
			 JOIN board_column lane
			   ON lane.id=card_record.column_id
			  AND lane.board_id=card_record.board_id
			  AND lane.is_archived=false
			 JOIN workspace_member membership
			   ON membership.workspace_id=card_record.workspace_id
			  AND membership.user_id=CAST(:userId AS UUID)
			 WHERE card_record.board_id=CAST(:boardId AS UUID)
			   AND card_record.workspace_id=CAST(:workspaceId AS UUID)
			   AND card_record.archived_at IS NULL
			   AND (
			       lane.is_hidden_from_members=false
			       OR membership.role IN ('owner','admin')
			   )
			 ORDER BY lane.position,card_record.position,
			          card_record.created_at,card_record.id",
			{
				userId=arguments.principal.userId,
				workspaceId=arguments.principal.workspaceId,
				boardId=arguments.boardId
			},
			{ returntype="array" }
		);

		var cards = cardDtos( rows );
		appendAssignees( arguments.principal, cards );
		return { found=true,cards=cards };
	}

	struct function getCard( required struct principal, required string cardId ){
		var rows = queryExecute(
			"SELECT CAST(card_record.id AS TEXT) AS id,
			        CAST(card_record.board_id AS TEXT) AS board_id,
			        CAST(card_record.column_id AS TEXT) AS lane_id,
			        card_record.title,COALESCE(card_record.description,'') AS description,
			        card_record.priority,
			        array_to_string(card_record.labels, ',') AS labels_csv,
			        card_record.position,card_record.version,
			        COALESCE(to_char(card_record.due_at AT TIME ZONE 'UTC',
			                         'YYYY-MM-DD""T""HH24:MI:SS""Z""'),'') AS due_at,
			        COALESCE(to_char(card_record.completed_at AT TIME ZONE 'UTC',
			                         'YYYY-MM-DD""T""HH24:MI:SS""Z""'),'') AS completed_at,
			        COALESCE(to_char(card_record.blocked_at AT TIME ZONE 'UTC',
			                         'YYYY-MM-DD""T""HH24:MI:SS""Z""'),'') AS blocked_at,
			        to_char(card_record.created_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS""Z""') AS created_at,
			        to_char(card_record.updated_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS""Z""') AS updated_at
			 FROM card card_record
			 JOIN board board_record
			   ON board_record.id=card_record.board_id
			  AND board_record.workspace_id=card_record.workspace_id
			  AND board_record.is_archived=false
			 JOIN board_column lane
			   ON lane.id=card_record.column_id
			  AND lane.board_id=card_record.board_id
			  AND lane.is_archived=false
			 JOIN workspace_member membership
			   ON membership.workspace_id=card_record.workspace_id
			  AND membership.user_id=CAST(:userId AS UUID)
			 WHERE card_record.id=CAST(:cardId AS UUID)
			   AND card_record.workspace_id=CAST(:workspaceId AS UUID)
			   AND card_record.archived_at IS NULL
			   AND (
			       lane.is_hidden_from_members=false
			       OR membership.role IN ('owner','admin')
			   )",
			{
				userId=arguments.principal.userId,
				workspaceId=arguments.principal.workspaceId,
				cardId=arguments.cardId
			},
			{ returntype="array" }
		);
		if ( !rows.len() ) return { found=false };

		var cards = cardDtos( rows );
		appendAssignees( arguments.principal, cards );
		return { found=true,card=cards[ 1 ] };
	}

	private array function cardDtos( required array rows ){
		var cards = [];
		for ( var row in arguments.rows ) cards.append( cardDto( row ) );
		return cards;
	}

	private void function appendAssignees(
		required struct principal,
		required array cards
	){
		if ( !arguments.cards.len() ) return;

		var cardMap = {};
		var cardIds = [];
		for ( var card in arguments.cards ) {
			cardMap[ card.id ] = card;
			cardIds.append( card.id );
		}
		var assignments = queryExecute(
			"SELECT CAST(assignment.card_id AS TEXT) AS card_id,
			        CAST(assignment.user_id AS TEXT) AS user_id
			 FROM card_assignee assignment
			 JOIN card card_record
			   ON card_record.id=assignment.card_id
			  AND card_record.workspace_id=assignment.workspace_id
			 JOIN workspace_member assigned_member
			   ON assigned_member.workspace_id=assignment.workspace_id
			  AND assigned_member.user_id=assignment.user_id
			 JOIN jsonb_array_elements_text(CAST(:cardIds AS JSONB)) requested(card_id)
			   ON assignment.card_id=CAST(requested.card_id AS UUID)
			 WHERE assignment.workspace_id=CAST(:workspaceId AS UUID)
			 ORDER BY assignment.created_at,assignment.user_id",
			{
				workspaceId=arguments.principal.workspaceId,
				cardIds=serializeJSON( cardIds )
			},
			{ returntype="array" }
		);
		for ( var assignment in assignments ) {
			if ( structKeyExists( cardMap, assignment.card_id ) ) {
				cardMap[ assignment.card_id ].assigneeIds.append( assignment.user_id );
			}
		}
	}

	private struct function boardDto( required struct row ){
		var dto = structNew( "ordered" );
		dto[ "id" ] = arguments.row.id;
		dto[ "name" ] = arguments.row.name;
		dto[ "description" ] = arguments.row.description;
		dto[ "position" ] = val( arguments.row.position );
		dto[ "createdAt" ] = arguments.row.created_at;
		dto[ "updatedAt" ] = arguments.row.updated_at;
		return dto;
	}

	private struct function laneDto( required struct row ){
		var dto = structNew( "ordered" );
		dto[ "id" ] = arguments.row.id;
		dto[ "name" ] = arguments.row.name;
		dto[ "position" ] = val( arguments.row.position );
		if (
			structKeyExists( arguments.row, "wip_limit" )
			&& !isNull( arguments.row.wip_limit )
			&& toString( arguments.row.wip_limit ).len()
		) dto[ "wipLimit" ] = val( arguments.row.wip_limit );
		dto[ "color" ] = arguments.row.color;
		dto[ "isCompletionLane" ] = listFindNoCase(
			"1,true,yes,t",
			lCase( trim( toString( arguments.row.is_completion_lane ?: false ) ) )
		) > 0;
		return dto;
	}

	private struct function cardDto( required struct row ){
		var dto = structNew( "ordered" );
		dto[ "id" ] = arguments.row.id;
		dto[ "boardId" ] = arguments.row.board_id;
		dto[ "laneId" ] = arguments.row.lane_id;
		dto[ "title" ] = arguments.row.title;
		dto[ "description" ] = arguments.row.description;
		dto[ "priority" ] = arguments.row.priority;
		dto[ "labels" ] = trim( arguments.row.labels_csv ?: "" ).len()
			? listToArray( arguments.row.labels_csv )
			: [];
		dto[ "assigneeIds" ] = [];
		dto[ "position" ] = val( arguments.row.position );
		dto[ "version" ] = val( arguments.row.version );
		dto[ "dueAt" ] = arguments.row.due_at;
		dto[ "isCompleted" ] = trim( arguments.row.completed_at ).len() > 0;
		dto[ "completedAt" ] = arguments.row.completed_at;
		dto[ "isBlocked" ] = trim( arguments.row.blocked_at ).len() > 0;
		dto[ "blockedAt" ] = arguments.row.blocked_at;
		dto[ "createdAt" ] = arguments.row.created_at;
		dto[ "updatedAt" ] = arguments.row.updated_at;
		return dto;
	}

}
