component singleton {

	struct function getPage(
		required string userId,
		required string workspaceId,
		numeric page = 1,
		numeric pageSize = 20,
		string filter = "all"
	){
		var safeFilter = lCase( trim( arguments.filter ) );
		var safePage = max( 1, fix( val( arguments.page ) ) );
		var safePageSize = min( 100, max( 1, fix( val( arguments.pageSize ) ) ) );
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
		) {
			return pageFailure( "not_found", safeFilter, safePage, safePageSize );
		}
		if ( !listFindNoCase( "all,unread", safeFilter ) ) {
			return pageFailure( "invalid_filter", "all", safePage, safePageSize );
		}

		var accessRows = queryExecute(
			"SELECT role
			 FROM workspace_member
			 WHERE workspace_id=CAST(:workspaceId AS UUID)
			   AND user_id=CAST(:userId AS UUID)",
			{
				workspaceId=arguments.workspaceId,
				userId=arguments.userId
			},
			{ returntype="array" }
		);
		if ( !accessRows.len() ) {
			return pageFailure( "not_found", safeFilter, safePage, safePageSize );
		}

		var countRows = queryExecute(
			"SELECT
			     COUNT(*) FILTER (
			         WHERE :filter='all' OR notification.read_at IS NULL
			     ) AS total_count,
			     COUNT(*) FILTER (
			         WHERE notification.read_at IS NULL
			     ) AS unread_count
			 FROM app_notification notification
			 JOIN workspace_member requester
			   ON requester.workspace_id=notification.workspace_id
			  AND requester.user_id=CAST(:userId AS UUID)
			 LEFT JOIN card card_record
			   ON lower(notification.aggregate_type)='card'
			  AND card_record.id=notification.aggregate_id
			  AND card_record.workspace_id=notification.workspace_id
			 LEFT JOIN board board_record
			   ON board_record.id=card_record.board_id
			  AND board_record.workspace_id=card_record.workspace_id
			 LEFT JOIN board_column lane_record
			   ON lane_record.id=card_record.column_id
			  AND lane_record.board_id=card_record.board_id
			 WHERE notification.workspace_id=CAST(:workspaceId AS UUID)
			   AND notification.user_id=CAST(:userId AS UUID)
			   AND (
			       lower(notification.aggregate_type)<>'card'
			       OR (
			           card_record.id IS NOT NULL
			           AND card_record.archived_at IS NULL
			           AND board_record.is_archived=false
			           AND lane_record.is_archived=false
			           AND (
			               lane_record.is_hidden_from_members=false
			               OR requester.role IN ('owner','admin')
			           )
			       )
			   )",
			{
				workspaceId=arguments.workspaceId,
				userId=arguments.userId,
				filter=safeFilter
			},
			{ returntype="array" }
		);
		var total = integerOrZero( countRows[ 1 ].total_count );
		var unread = integerOrZero( countRows[ 1 ].unread_count );
		var totalPages = total > 0 ? ceiling( total / safePageSize ) : 0;
		safePage = min( safePage, max( 1, totalPages ) );
		var offset = ( safePage - 1 ) * safePageSize;

		var itemRows = queryExecute(
			"SELECT CAST(notification.id AS TEXT) AS id,
			        notification.notification_type,
			        notification.aggregate_type,
			        CAST(notification.aggregate_id AS TEXT) AS aggregate_id,
			        notification.payload,
			        to_char(
			            notification.created_at AT TIME ZONE 'UTC',
			            'YYYY-MM-DD""T""HH24:MI:SS.MS""Z""'
			        ) AS created_at,
			        COALESCE(
			            to_char(
			                notification.read_at AT TIME ZONE 'UTC',
			                'YYYY-MM-DD""T""HH24:MI:SS.MS""Z""'
			            ),
			            ''
			        ) AS read_at,
			        COALESCE(actor.display_name,'') AS actor_name,
			        COALESCE(CAST(actor_avatar.id AS TEXT),'') AS actor_avatar_id,
			        COALESCE(CAST(card_record.id AS TEXT),'') AS card_id,
			        COALESCE(card_record.title,'') AS card_title,
			        COALESCE(
			            CAST(card_board.id AS TEXT),
			            CAST(aggregate_board.id AS TEXT),
			            ''
			        ) AS board_id,
			        COALESCE(card_board.name,aggregate_board.name,'') AS board_name,
			        COALESCE(lane_record.name,'') AS lane_name
			 FROM app_notification notification
			 JOIN workspace_member requester
			   ON requester.workspace_id=notification.workspace_id
			  AND requester.user_id=CAST(:userId AS UUID)
			 LEFT JOIN workspace_member actor_membership
			   ON actor_membership.workspace_id=notification.workspace_id
			  AND actor_membership.user_id=notification.actor_id
			 LEFT JOIN app_user actor
			   ON actor.id=actor_membership.user_id
			 LEFT JOIN user_avatar actor_avatar
			   ON actor_avatar.user_id=actor.id
			  AND actor_avatar.status='available'
			  AND actor_avatar.deleted_at IS NULL
			 LEFT JOIN card card_record
			   ON lower(notification.aggregate_type)='card'
			  AND card_record.id=notification.aggregate_id
			  AND card_record.workspace_id=notification.workspace_id
			 LEFT JOIN board card_board
			   ON card_board.id=card_record.board_id
			  AND card_board.workspace_id=card_record.workspace_id
			 LEFT JOIN board_column lane_record
			   ON lane_record.id=card_record.column_id
			  AND lane_record.board_id=card_record.board_id
			 LEFT JOIN board aggregate_board
			   ON lower(notification.aggregate_type)='board'
			  AND aggregate_board.id=notification.aggregate_id
			  AND aggregate_board.workspace_id=notification.workspace_id
			  AND aggregate_board.is_archived=false
			 WHERE notification.workspace_id=CAST(:workspaceId AS UUID)
			   AND notification.user_id=CAST(:userId AS UUID)
			   AND ( :filter='all' OR notification.read_at IS NULL )
			   AND (
			       lower(notification.aggregate_type)<>'card'
			       OR (
			           card_record.id IS NOT NULL
			           AND card_record.archived_at IS NULL
			           AND card_board.is_archived=false
			           AND lane_record.is_archived=false
			           AND (
			               lane_record.is_hidden_from_members=false
			               OR requester.role IN ('owner','admin')
			           )
			       )
			   )
			 ORDER BY notification.created_at DESC,notification.id DESC
			 LIMIT CAST(:pageSize AS INTEGER)
			 OFFSET CAST(:offset AS INTEGER)",
			{
				workspaceId=arguments.workspaceId,
				userId=arguments.userId,
				filter=safeFilter,
				pageSize=safePageSize,
				offset=offset
			},
			{ returntype="array" }
		);

		var items = [];
		for ( var itemRow in itemRows ) {
			var item = {};
			item[ "id" ] = itemRow.id;
			item[ "type" ] = itemRow.notification_type;
			item[ "eventType" ] = itemRow.notification_type;
			item[ "actorName" ] = itemRow.actor_name;
			item[ "actorInitials" ] = initials( itemRow.actor_name );
			item[ "actorAvatarId" ] = itemRow.actor_avatar_id;
			item[ "cardId" ] = itemRow.card_id;
			item[ "cardTitle" ] = itemRow.card_title;
			item[ "boardId" ] = itemRow.board_id;
			item[ "boardName" ] = itemRow.board_name;
			item[ "laneName" ] = itemRow.lane_name;
			item[ "createdAt" ] = itemRow.created_at;
			item[ "readAt" ] = itemRow.read_at;
			item[ "isRead" ] = ( itemRow.read_at ?: "" ).len() > 0;
			item[ "targetUrl" ] = actionUrl(
				itemRow.aggregate_type,
				itemRow.notification_type,
				itemRow.card_id,
				itemRow.board_id
			);
			item[ "payload" ] = jsonObject( itemRow.payload );
			items.append( item );
		}

		var result = {};
		result[ "found" ] = true;
		result[ "code" ] = "ok";
		result[ "items" ] = items;
		result[ "page" ] = safePage;
		result[ "pageSize" ] = safePageSize;
		result[ "total" ] = total;
		result[ "totalPages" ] = totalPages;
		result[ "filter" ] = safeFilter;
		result[ "unreadCount" ] = unread;
		return result;
	}

	numeric function unreadCount(
		required string userId,
		required string workspaceId
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
		) return 0;

		var rows = queryExecute(
			"SELECT COUNT(*) AS unread_count
			 FROM app_notification notification
			 JOIN workspace_member requester
			   ON requester.workspace_id=notification.workspace_id
			  AND requester.user_id=CAST(:userId AS UUID)
			 LEFT JOIN card card_record
			   ON lower(notification.aggregate_type)='card'
			  AND card_record.id=notification.aggregate_id
			  AND card_record.workspace_id=notification.workspace_id
			 LEFT JOIN board board_record
			   ON board_record.id=card_record.board_id
			  AND board_record.workspace_id=card_record.workspace_id
			 LEFT JOIN board_column lane_record
			   ON lane_record.id=card_record.column_id
			  AND lane_record.board_id=card_record.board_id
			 WHERE notification.workspace_id=CAST(:workspaceId AS UUID)
			   AND notification.user_id=CAST(:userId AS UUID)
			   AND notification.read_at IS NULL
			   AND (
			       lower(notification.aggregate_type)<>'card'
			       OR (
			           card_record.id IS NOT NULL
			           AND card_record.archived_at IS NULL
			           AND board_record.is_archived=false
			           AND lane_record.is_archived=false
			           AND (
			               lane_record.is_hidden_from_members=false
			               OR requester.role IN ('owner','admin')
			           )
			       )
			   )",
			{
				workspaceId=arguments.workspaceId,
				userId=arguments.userId
			},
			{ returntype="array" }
		);
		return integerOrZero( rows[ 1 ].unread_count );
	}

	struct function markRead(
		required string userId,
		required string workspaceId,
		required string notificationId
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.notificationId )
		) return mutationFailure( "not_found" );

		var updatedRows = queryExecute(
			"UPDATE app_notification notification
			 SET read_at=COALESCE(notification.read_at,now())
			 FROM workspace_member requester
			 WHERE notification.id=CAST(:notificationId AS UUID)
			   AND notification.workspace_id=CAST(:workspaceId AS UUID)
			   AND notification.user_id=CAST(:userId AS UUID)
			   AND requester.workspace_id=notification.workspace_id
			   AND requester.user_id=CAST(:userId AS UUID)
			   AND (
			       lower(notification.aggregate_type)<>'card'
			       OR EXISTS (
			           SELECT 1
			           FROM card card_record
			           JOIN board board_record
			             ON board_record.id=card_record.board_id
			            AND board_record.workspace_id=card_record.workspace_id
			           JOIN board_column lane_record
			             ON lane_record.id=card_record.column_id
			            AND lane_record.board_id=card_record.board_id
			           WHERE card_record.id=notification.aggregate_id
			             AND card_record.workspace_id=notification.workspace_id
			             AND card_record.archived_at IS NULL
			             AND board_record.is_archived=false
			             AND lane_record.is_archived=false
			             AND (
			                 lane_record.is_hidden_from_members=false
			                 OR requester.role IN ('owner','admin')
			             )
			       )
			   )
			 RETURNING CAST(notification.id AS TEXT) AS id,
			           notification.notification_type,
			           notification.aggregate_type,
			           CAST(notification.aggregate_id AS TEXT) AS aggregate_id",
			{
				notificationId=arguments.notificationId,
				workspaceId=arguments.workspaceId,
				userId=arguments.userId
			},
			{ returntype="array" }
		);
		if ( !updatedRows.len() ) return mutationFailure( "not_found" );

		var result = {};
		result[ "success" ] = true;
		result[ "code" ] = "ok";
		result[ "id" ] = updatedRows[ 1 ].id;
		var aggregateId = updatedRows[ 1 ].aggregate_id;
		var cardId = compareNoCase( updatedRows[ 1 ].aggregate_type, "card" ) == 0
			? aggregateId
			: "";
		var boardId = compareNoCase( updatedRows[ 1 ].aggregate_type, "board" ) == 0
			? aggregateId
			: "";
		result[ "targetUrl" ] = actionUrl(
			updatedRows[ 1 ].aggregate_type,
			updatedRows[ 1 ].notification_type,
			cardId,
			boardId
		);
		result[ "unreadCount" ] = unreadCount(
			arguments.userId,
			arguments.workspaceId
		);
		return result;
	}

	struct function markAllRead(
		required string userId,
		required string workspaceId
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
		) return mutationFailure( "not_found" );
		if ( !hasMembership( arguments.userId, arguments.workspaceId ) ) {
			return mutationFailure( "not_found" );
		}

		var updatedRows = queryExecute(
			"UPDATE app_notification notification
			 SET read_at=now()
			 FROM workspace_member requester
			 WHERE notification.workspace_id=CAST(:workspaceId AS UUID)
			   AND notification.user_id=CAST(:userId AS UUID)
			   AND notification.read_at IS NULL
			   AND requester.workspace_id=notification.workspace_id
			   AND requester.user_id=CAST(:userId AS UUID)
			   AND (
			       lower(notification.aggregate_type)<>'card'
			       OR EXISTS (
			           SELECT 1
			           FROM card card_record
			           JOIN board board_record
			             ON board_record.id=card_record.board_id
			            AND board_record.workspace_id=card_record.workspace_id
			           JOIN board_column lane_record
			             ON lane_record.id=card_record.column_id
			            AND lane_record.board_id=card_record.board_id
			           WHERE card_record.id=notification.aggregate_id
			             AND card_record.workspace_id=notification.workspace_id
			             AND card_record.archived_at IS NULL
			             AND board_record.is_archived=false
			             AND lane_record.is_archived=false
			             AND (
			                 lane_record.is_hidden_from_members=false
			                 OR requester.role IN ('owner','admin')
			             )
			       )
			   )
			 RETURNING CAST(notification.id AS TEXT) AS id",
			{
				workspaceId=arguments.workspaceId,
				userId=arguments.userId
			},
			{ returntype="array" }
		);
		var result = {};
		result[ "success" ] = true;
		result[ "code" ] = "ok";
		result[ "updated" ] = updatedRows.len();
		result[ "unreadCount" ] = unreadCount(
			arguments.userId,
			arguments.workspaceId
		);
		return result;
	}

	private struct function pageFailure(
		required string code,
		required string filter,
		required numeric page,
		required numeric pageSize
	){
		var result = {};
		result[ "found" ] = false;
		result[ "code" ] = arguments.code;
		result[ "items" ] = [];
		result[ "page" ] = arguments.page;
		result[ "pageSize" ] = arguments.pageSize;
		result[ "total" ] = 0;
		result[ "totalPages" ] = 0;
		result[ "filter" ] = arguments.filter;
		result[ "unreadCount" ] = 0;
		return result;
	}

	private struct function mutationFailure( required string code ){
		var result = {};
		result[ "success" ] = false;
		result[ "code" ] = arguments.code;
		result[ "id" ] = "";
		result[ "updated" ] = 0;
		result[ "unreadCount" ] = 0;
		result[ "targetUrl" ] = "";
		return result;
	}

	private struct function jsonObject( any value ){
		if ( isNull( arguments.value ) ) return {};
		if ( isStruct( arguments.value ) ) return arguments.value;
		try {
			var decoded = deserializeJSON( toString( arguments.value ) );
			return isStruct( decoded ) ? decoded : {};
		} catch ( any ignored ) {
			return {};
		}
	}

	private string function actionUrl(
		required string aggregateType,
		required string eventType,
		required string cardId,
		required string boardId
	){
		if ( isCanonicalUuid( arguments.cardId ) ) {
			return "/app/cards/#lCase( arguments.cardId )#";
		}
		if ( isCanonicalUuid( arguments.boardId ) ) {
			return "/app?boardId=#urlEncodedFormat( lCase( arguments.boardId ) )#";
		}
		var normalizedEventType = lCase( arguments.eventType );
		if (
			find( "member", normalizedEventType )
			|| find( "invitation", normalizedEventType )
			|| find( "invite", normalizedEventType )
		) return "/app/members";
		if (
			find( "billing", normalizedEventType )
			|| find( "subscription", normalizedEventType )
			|| find( "payment", normalizedEventType )
		) return "/app/profile";
		return "/app";
	}

	private string function initials( required string displayName ){
		var cleanName = reReplace( trim( arguments.displayName ), "\s+", " ", "all" );
		if ( !cleanName.len() ) return "";
		var parts = listToArray( cleanName, " " );
		var result = left( parts[ 1 ], 1 );
		if ( parts.len() > 1 ) result &= left( parts[ parts.len() ], 1 );
		return uCase( result );
	}

	private numeric function integerOrZero( any value = 0 ){
		if ( isNull( arguments.value ) || !isNumeric( arguments.value ) ) return 0;
		return fix( val( arguments.value ) );
	}

	private boolean function hasMembership(
		required string userId,
		required string workspaceId
	){
		var rows = queryExecute(
			"SELECT 1
			 FROM workspace_member
			 WHERE workspace_id=CAST(:workspaceId AS UUID)
			   AND user_id=CAST(:userId AS UUID)",
			{
				workspaceId=arguments.workspaceId,
				userId=arguments.userId
			},
			{ returntype="array" }
		);
		return rows.len() > 0;
	}

	private boolean function isCanonicalUuid( required string value ){
		return reFindNoCase(
			"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
			trim( arguments.value )
		) > 0;
	}

}
