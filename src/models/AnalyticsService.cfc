component singleton {

	struct function getDashboard(
		required string userId,
		required string workspaceId,
		struct filters = {}
	){
		if ( !isCanonicalUuid( arguments.userId ) || !isCanonicalUuid( arguments.workspaceId ) ) {
			return failure( "not_found" );
		}

		var accessRows = queryExecute(
			"SELECT membership.role,workspace.plan
			 FROM workspace_member membership
			 JOIN workspace ON workspace.id=membership.workspace_id
			 WHERE membership.user_id=CAST(:userId AS UUID)
			   AND membership.workspace_id=CAST(:workspaceId AS UUID)",
			{
				userId=arguments.userId,
				workspaceId=arguments.workspaceId
			},
			{ returntype="array" }
		);
		if ( !accessRows.len() ) return failure( "not_found" );

		var access = {};
		access[ "role" ] = accessRows[ 1 ].role;
		access[ "plan" ] = accessRows[ 1 ].plan;
		access[ "canViewHiddenLanes" ] = listFindNoCase( "owner,admin", accessRows[ 1 ].role ) > 0;
		var normalized = normalizeFilters( arguments.filters );
		if ( !normalized.success ) return failure( normalized.code );

		if ( normalized.boardId.len() ) {
			var validBoard = queryExecute(
				"SELECT 1
				 FROM board
				 WHERE id=CAST(:boardId AS UUID)
				   AND workspace_id=CAST(:workspaceId AS UUID)",
				{
					boardId=normalized.boardId,
					workspaceId=arguments.workspaceId
				},
				{ returntype="array" }
			);
			if ( !validBoard.len() ) return failure( "not_found" );
		}

		if ( normalized.assigneeId.len() ) {
			var validAssignee = queryExecute(
				"SELECT 1
				 FROM workspace_member
				 WHERE workspace_id=CAST(:workspaceId AS UUID)
				   AND user_id=CAST(:assigneeId AS UUID)",
				{
					workspaceId=arguments.workspaceId,
					assigneeId=normalized.assigneeId
				},
				{ returntype="array" }
			);
			if ( !validAssignee.len() ) return failure( "invalid_filter" );
		}

		var params = {
			workspaceId=arguments.workspaceId,
			canViewHidden=access.canViewHiddenLanes,
			fromDate=normalized.from,
			toDate=normalized.to,
			utcToday=normalized.utcToday
		};
		var historicalPredicates = [
			"c.workspace_id=CAST(:workspaceId AS UUID)",
			"(bc.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))"
		];
		var currentPredicates = [
			"c.workspace_id=CAST(:workspaceId AS UUID)",
			"c.archived_at IS NULL",
			"c.completed_at IS NULL",
			"b.is_archived=false",
			"bc.is_archived=false",
			"(bc.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))"
		];
		if ( normalized.boardId.len() ) {
			params.boardId = normalized.boardId;
			historicalPredicates.append( "c.board_id=CAST(:boardId AS UUID)" );
			currentPredicates.append( "c.board_id=CAST(:boardId AS UUID)" );
		}
		if ( normalized.assigneeId.len() ) {
			params.assigneeId = normalized.assigneeId;
			historicalPredicates.append( "c.assignee_id=CAST(:assigneeId AS UUID)" );
			currentPredicates.append( "c.assignee_id=CAST(:assigneeId AS UUID)" );
		}

		var summaryRow = queryExecute(
			"WITH historical_scope AS (
			     SELECT c.id,c.created_at,c.started_at,c.completed_at,c.due_at,c.archived_at,
			            b.is_archived AS board_archived,bc.is_archived AS lane_archived
			     FROM card c
			     JOIN board b ON b.id=c.board_id AND b.workspace_id=c.workspace_id
			     JOIN board_column bc ON bc.id=c.column_id AND bc.board_id=c.board_id
			     WHERE #arrayToList( historicalPredicates, ' AND ' )#
			 ),
			 current_scope AS (
			     SELECT *
			     FROM historical_scope
			     WHERE archived_at IS NULL
			       AND completed_at IS NULL
			       AND board_archived=false
			       AND lane_archived=false
			 ),
			 period_completed AS (
			     SELECT *
			     FROM historical_scope
			     WHERE completed_at>=CAST(:fromDate AS DATE)
			       AND completed_at<CAST(:toDate AS DATE)+INTERVAL '1 day'
			 )
			 SELECT
			     (SELECT COUNT(*) FROM current_scope) AS open_cards,
			     (SELECT COUNT(*) FROM current_scope WHERE started_at IS NOT NULL) AS current_wip,
			     (SELECT COUNT(*) FROM current_scope
			       WHERE due_at IS NOT NULL
			         AND CAST(due_at AT TIME ZONE 'UTC' AS DATE)<CAST(:utcToday AS DATE)) AS overdue,
			     (SELECT COUNT(*) FROM current_scope
			       WHERE due_at IS NOT NULL
			         AND CAST(due_at AT TIME ZONE 'UTC' AS DATE)>=CAST(:utcToday AS DATE)
			         AND CAST(due_at AT TIME ZONE 'UTC' AS DATE)<=CAST(:utcToday AS DATE)+6) AS due_next_7_days,
			     COUNT(*) AS throughput,
			     COUNT(*) FILTER (WHERE completed_at>=created_at) AS lead_sample_size,
			     AVG(EXTRACT(EPOCH FROM completed_at-created_at))
			         FILTER (WHERE completed_at>=created_at) AS lead_average_seconds,
			     PERCENTILE_CONT(0.5) WITHIN GROUP (
			         ORDER BY EXTRACT(EPOCH FROM completed_at-created_at)
			     ) FILTER (WHERE completed_at>=created_at) AS lead_median_seconds,
			     PERCENTILE_CONT(0.85) WITHIN GROUP (
			         ORDER BY EXTRACT(EPOCH FROM completed_at-created_at)
			     ) FILTER (WHERE completed_at>=created_at) AS lead_p85_seconds,
			     COUNT(*) FILTER (
			         WHERE started_at IS NOT NULL AND completed_at>=started_at
			     ) AS cycle_sample_size,
			     AVG(EXTRACT(EPOCH FROM completed_at-started_at))
			         FILTER (WHERE started_at IS NOT NULL AND completed_at>=started_at) AS cycle_average_seconds,
			     PERCENTILE_CONT(0.5) WITHIN GROUP (
			         ORDER BY EXTRACT(EPOCH FROM completed_at-started_at)
			     ) FILTER (
			         WHERE started_at IS NOT NULL AND completed_at>=started_at
			     ) AS cycle_median_seconds,
			     PERCENTILE_CONT(0.85) WITHIN GROUP (
			         ORDER BY EXTRACT(EPOCH FROM completed_at-started_at)
			     ) FILTER (
			         WHERE started_at IS NOT NULL AND completed_at>=started_at
			     ) AS cycle_p85_seconds,
			     COUNT(*) FILTER (WHERE started_at IS NULL) AS missing_started_at,
			     COUNT(*) FILTER (WHERE completed_at<created_at) AS invalid_lead_time,
			     COUNT(*) FILTER (
			         WHERE started_at IS NOT NULL AND completed_at<started_at
			     ) AS invalid_cycle_time
			 FROM period_completed",
			params,
			{ returntype="array" }
		)[ 1 ];

		var throughputRows = queryExecute(
			"SELECT to_char(CAST(c.completed_at AT TIME ZONE 'UTC' AS DATE),'YYYY-MM-DD') AS bucket_date,
			        COUNT(*) AS completed_count
			 FROM card c
			 JOIN board b ON b.id=c.board_id AND b.workspace_id=c.workspace_id
			 JOIN board_column bc ON bc.id=c.column_id AND bc.board_id=c.board_id
			 WHERE #arrayToList( historicalPredicates, ' AND ' )#
			   AND c.completed_at>=CAST(:fromDate AS DATE)
			   AND c.completed_at<CAST(:toDate AS DATE)+INTERVAL '1 day'
			 GROUP BY CAST(c.completed_at AT TIME ZONE 'UTC' AS DATE)
			 ORDER BY CAST(c.completed_at AT TIME ZONE 'UTC' AS DATE)",
			params,
			{ returntype="array" }
		);
		var throughputByDate = {};
		for ( var throughputRow in throughputRows ) {
			throughputByDate[ throughputRow.bucket_date ] = integerOrZero( throughputRow.completed_count );
		}
		var throughputTrend = [];
		var inclusiveDays = dateDiff( "d", normalized.fromDate, normalized.toDate ) + 1;
		for ( var dayOffset=0; dayOffset<inclusiveDays; dayOffset++ ) {
			var bucketDate = dateFormat( dateAdd( "d", dayOffset, normalized.fromDate ), "yyyy-mm-dd" );
			var throughputPoint = {};
			throughputPoint[ "date" ] = bucketDate;
			throughputPoint[ "count" ] = structKeyExists( throughputByDate, bucketDate )
				? throughputByDate[ bucketDate ]
				: 0;
			throughputTrend.append( throughputPoint );
		}

		var lanePredicates = [
			"b.workspace_id=CAST(:workspaceId AS UUID)",
			"b.is_archived=false",
			"bc.is_archived=false",
			"(bc.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))"
		];
		var laneCardPredicates = [
			"c.column_id=bc.id",
			"c.board_id=b.id",
			"c.workspace_id=b.workspace_id",
			"c.archived_at IS NULL",
			"c.completed_at IS NULL"
		];
		if ( normalized.boardId.len() ) lanePredicates.append( "b.id=CAST(:boardId AS UUID)" );
		if ( normalized.assigneeId.len() ) {
			laneCardPredicates.append( "c.assignee_id=CAST(:assigneeId AS UUID)" );
		}
		var laneRows = queryExecute(
			"SELECT CAST(b.id AS TEXT) AS board_id,b.name AS board_name,
			        CAST(bc.id AS TEXT) AS lane_id,bc.name AS lane_name,bc.color,
			        bc.is_hidden_from_members,COUNT(c.id) AS card_count
			 FROM board b
			 JOIN board_column bc ON bc.board_id=b.id
			 LEFT JOIN card c ON #arrayToList( laneCardPredicates, ' AND ' )#
			 WHERE #arrayToList( lanePredicates, ' AND ' )#
			 GROUP BY b.id,bc.id
			 ORDER BY b.position,b.created_at,b.name,bc.position,bc.created_at",
			params,
			{ returntype="array" }
		);
		var cardsByLane = [];
		for ( var laneRow in laneRows ) {
			var lanePoint = {};
			lanePoint[ "boardId" ] = laneRow.board_id;
			lanePoint[ "boardName" ] = laneRow.board_name;
			lanePoint[ "laneId" ] = laneRow.lane_id;
			lanePoint[ "laneName" ] = laneRow.lane_name;
			lanePoint[ "color" ] = laneRow.color;
			lanePoint[ "hiddenFromMembers" ] = laneRow.is_hidden_from_members ?: false;
			lanePoint[ "cardCount" ] = integerOrZero( laneRow.card_count );
			cardsByLane.append( lanePoint );
		}

		var agingRows = queryExecute(
			"SELECT CAST(c.id AS TEXT) AS card_id,c.title,
			        CAST(b.id AS TEXT) AS board_id,b.name AS board_name,
			        CAST(bc.id AS TEXT) AS lane_id,bc.name AS lane_name,bc.color AS lane_color,
			        to_char(c.created_at AT TIME ZONE 'UTC','YYYY-MM-DD""T""HH24:MI:SS.MS""Z""') AS created_at,
			        COALESCE(
			            to_char(c.started_at AT TIME ZONE 'UTC','YYYY-MM-DD""T""HH24:MI:SS.MS""Z""'),
			            ''
			        ) AS started_at,
			        to_char(
			            COALESCE(last_move.occurred_at,c.created_at) AT TIME ZONE 'UTC',
			            'YYYY-MM-DD""T""HH24:MI:SS.MS""Z""'
			        ) AS lane_entered_at,
			        ROUND(EXTRACT(EPOCH FROM now()-c.created_at)) AS card_age_seconds,
			        CASE WHEN c.started_at IS NOT NULL
			             THEN ROUND(EXTRACT(EPOCH FROM now()-c.started_at))
			        END AS wip_age_seconds,
			        ROUND(
			            EXTRACT(EPOCH FROM now()-COALESCE(last_move.occurred_at,c.created_at))
			        ) AS lane_age_seconds
			 FROM card c
			 JOIN board b ON b.id=c.board_id AND b.workspace_id=c.workspace_id
			 JOIN board_column bc ON bc.id=c.column_id AND bc.board_id=c.board_id
			 LEFT JOIN LATERAL (
			     SELECT transition.occurred_at
			     FROM card_transition transition
			     WHERE transition.workspace_id=c.workspace_id
			       AND transition.card_id=c.id
			       AND transition.to_column_id=c.column_id
			     ORDER BY transition.occurred_at DESC
			     LIMIT 1
			 ) last_move ON true
			 WHERE #arrayToList( currentPredicates, ' AND ' )#
			 ORDER BY COALESCE(last_move.occurred_at,c.created_at),c.created_at,c.id
			 LIMIT 10",
			params,
			{ returntype="array" }
		);
		var agingCards = [];
		for ( var agingRow in agingRows ) {
			var agingCard = {};
			agingCard[ "cardId" ] = agingRow.card_id;
			agingCard[ "title" ] = agingRow.title;
			agingCard[ "boardId" ] = agingRow.board_id;
			agingCard[ "boardName" ] = agingRow.board_name;
			agingCard[ "laneId" ] = agingRow.lane_id;
			agingCard[ "laneName" ] = agingRow.lane_name;
			agingCard[ "laneColor" ] = agingRow.lane_color;
			agingCard[ "createdAt" ] = agingRow.created_at;
			agingCard[ "startedAt" ] = agingRow.started_at;
			agingCard[ "laneEnteredAt" ] = agingRow.lane_entered_at;
			agingCard[ "hasStarted" ] = ( agingRow.started_at ?: "" ).len() > 0;
			agingCard[ "cardAgeSeconds" ] = integerOrZero( agingRow.card_age_seconds );
			agingCard[ "wipAgeSeconds" ] = integerOrZero( agingRow.wip_age_seconds ?: 0 );
			agingCard[ "laneAgeSeconds" ] = integerOrZero( agingRow.lane_age_seconds );
			agingCards.append( agingCard );
		}

		var priorityRows = queryExecute(
			"SELECT c.priority,COUNT(*) AS card_count
			 FROM card c
			 JOIN board b ON b.id=c.board_id AND b.workspace_id=c.workspace_id
			 JOIN board_column bc ON bc.id=c.column_id AND bc.board_id=c.board_id
			 WHERE #arrayToList( currentPredicates, ' AND ' )#
			 GROUP BY c.priority",
			params,
			{ returntype="array" }
		);
		var priorityCounts = {
			none=0,
			low=0,
			medium=0,
			high=0,
			urgent=0
		};
		for ( var priorityRow in priorityRows ) {
			priorityCounts[ priorityRow.priority ] = integerOrZero( priorityRow.card_count );
		}
		var priorityDistribution = [];
		for ( var priority in [ "none", "low", "medium", "high", "urgent" ] ) {
			var priorityPoint = {};
			priorityPoint[ "priority" ] = priority;
			priorityPoint[ "count" ] = priorityCounts[ priority ];
			priorityDistribution.append( priorityPoint );
		}

		var assigneeRows = queryExecute(
			"SELECT COALESCE(CAST(c.assignee_id AS TEXT),'') AS assignee_id,
			        COALESCE(assigned_user.display_name,'') AS assignee_name,
			        COUNT(*) AS card_count
			 FROM card c
			 JOIN board b ON b.id=c.board_id AND b.workspace_id=c.workspace_id
			 JOIN board_column bc ON bc.id=c.column_id AND bc.board_id=c.board_id
			 LEFT JOIN app_user assigned_user ON assigned_user.id=c.assignee_id
			 WHERE #arrayToList( currentPredicates, ' AND ' )#
			 GROUP BY c.assignee_id,assigned_user.display_name
			 ORDER BY COUNT(*) DESC,assigned_user.display_name NULLS LAST",
			params,
			{ returntype="array" }
		);
		var assigneeDistribution = [];
		for ( var assigneeRow in assigneeRows ) {
			var assigneePoint = {};
			assigneePoint[ "assigneeId" ] = assigneeRow.assignee_id;
			assigneePoint[ "assigneeName" ] = assigneeRow.assignee_name;
			assigneePoint[ "unassigned" ] = !( assigneeRow.assignee_id ?: "" ).len();
			assigneePoint[ "count" ] = integerOrZero( assigneeRow.card_count );
			assigneeDistribution.append( assigneePoint );
		}

		var throughput = integerOrZero( summaryRow.throughput );
		var cycleSamples = integerOrZero( summaryRow.cycle_sample_size );
		var missingStartedAt = integerOrZero( summaryRow.missing_started_at );
		var warnings = [
			"completion_uses_last_visible_lane",
			"cycle_time_starts_on_first_lane_change",
			"historical_throughput_uses_latest_completion"
		];
		if ( missingStartedAt > 0 ) warnings.append( "completed_cards_missing_started_at" );
		if ( normalized.assigneeId.len() ) warnings.append( "assignee_filter_uses_current_assignment" );

		var responseFilters = {};
		responseFilters[ "boardId" ] = normalized.boardId;
		responseFilters[ "assigneeId" ] = normalized.assigneeId;

		var responsePeriod = {};
		responsePeriod[ "from" ] = normalized.from;
		responsePeriod[ "to" ] = normalized.to;
		responsePeriod[ "toExclusive" ] = dateFormat(
			dateAdd( "d", 1, normalized.toDate ),
			"yyyy-mm-dd"
		);
		responsePeriod[ "days" ] = inclusiveDays;
		responsePeriod[ "timezone" ] = "UTC";

		var leadTime = {};
		leadTime[ "sampleSize" ] = integerOrZero( summaryRow.lead_sample_size );
		leadTime[ "averageSeconds" ] = integerOrZero( summaryRow.lead_average_seconds ?: 0 );
		leadTime[ "medianSeconds" ] = integerOrZero( summaryRow.lead_median_seconds ?: 0 );
		leadTime[ "p85Seconds" ] = integerOrZero( summaryRow.lead_p85_seconds ?: 0 );

		var cycleTime = {};
		cycleTime[ "sampleSize" ] = cycleSamples;
		cycleTime[ "averageSeconds" ] = integerOrZero( summaryRow.cycle_average_seconds ?: 0 );
		cycleTime[ "medianSeconds" ] = integerOrZero( summaryRow.cycle_median_seconds ?: 0 );
		cycleTime[ "p85Seconds" ] = integerOrZero( summaryRow.cycle_p85_seconds ?: 0 );

		var summary = {};
		summary[ "openCards" ] = integerOrZero( summaryRow.open_cards );
		summary[ "currentWip" ] = integerOrZero( summaryRow.current_wip );
		summary[ "throughput" ] = throughput;
		summary[ "overdue" ] = integerOrZero( summaryRow.overdue );
		summary[ "dueNext7Days" ] = integerOrZero( summaryRow.due_next_7_days );
		summary[ "leadTime" ] = leadTime;
		summary[ "cycleTime" ] = cycleTime;

		var dataQuality = {};
		dataQuality[ "completedSamples" ] = throughput;
		dataQuality[ "leadSamples" ] = integerOrZero( summaryRow.lead_sample_size );
		dataQuality[ "cycleSamples" ] = cycleSamples;
		dataQuality[ "missingStartedAt" ] = missingStartedAt;
		dataQuality[ "invalidLeadTime" ] = integerOrZero( summaryRow.invalid_lead_time );
		dataQuality[ "invalidCycleTime" ] = integerOrZero( summaryRow.invalid_cycle_time );
		dataQuality[ "cycleCoveragePercent" ] = throughput > 0
			? round( cycleSamples * 1000 / throughput ) / 10
			: 0;
		dataQuality[ "semanticsVersion" ] = "legacy-v1";
		dataQuality[ "warnings" ] = warnings;

		var dashboard = {};
		dashboard[ "found" ] = true;
		dashboard[ "code" ] = "ok";
		dashboard[ "access" ] = access;
		dashboard[ "filters" ] = responseFilters;
		dashboard[ "period" ] = responsePeriod;
		dashboard[ "summary" ] = summary;
		dashboard[ "throughputTrend" ] = throughputTrend;
		dashboard[ "cardsByLane" ] = cardsByLane;
		dashboard[ "agingCards" ] = agingCards;
		dashboard[ "priorityDistribution" ] = priorityDistribution;
		dashboard[ "assigneeDistribution" ] = assigneeDistribution;
		dashboard[ "dataQuality" ] = dataQuality;
		return dashboard;
	}

	private struct function normalizeFilters( required struct filters ){
		var normalized = {
			success=true,
			code="ok",
			boardId=trim( arguments.filters.boardId ?: "" ),
			assigneeId=trim( arguments.filters.assigneeId ?: "" )
		};
		if (
			( normalized.boardId.len() && !isCanonicalUuid( normalized.boardId ) )
			|| ( normalized.assigneeId.len() && !isCanonicalUuid( normalized.assigneeId ) )
		) {
			return { success=false,code="invalid_filter" };
		}

		var utcToday = createObject( "java", "java.time.LocalDate" )
			.now( createObject( "java", "java.time.ZoneId" ).of( "UTC" ) )
			.toString();
		var parsedUtcToday = parseIsoDate( utcToday );
		var today = parsedUtcToday.value;
		var rawTo = trim( arguments.filters.toDate ?: ( arguments.filters.to ?: "" ) );
		var parsedTo = rawTo.len() ? parseIsoDate( rawTo ) : { success=true,value=today };
		if ( !parsedTo.success ) return { success=false,code="invalid_period" };

		var rawFrom = trim( arguments.filters.fromDate ?: ( arguments.filters.from ?: "" ) );
		var parsedFrom = rawFrom.len()
			? parseIsoDate( rawFrom )
			: { success=true,value=dateAdd( "d", -29, parsedTo.value ) };
		if ( !parsedFrom.success ) return { success=false,code="invalid_period" };

		var span = dateDiff( "d", parsedFrom.value, parsedTo.value );
		if ( span < 0 || span + 1 > 366 ) return { success=false,code="invalid_period" };

		normalized.fromDate = parsedFrom.value;
		normalized.toDate = parsedTo.value;
		normalized.from = dateFormat( parsedFrom.value, "yyyy-mm-dd" );
		normalized.to = dateFormat( parsedTo.value, "yyyy-mm-dd" );
		normalized.utcToday = utcToday;
		return normalized;
	}

	private struct function parseIsoDate( required string value ){
		if ( !reFind( "^\d{4}-\d{2}-\d{2}$", arguments.value ) ) {
			return { success=false };
		}
		try {
			var pieces = listToArray( arguments.value, "-" );
			var parsed = createDate( val( pieces[ 1 ] ), val( pieces[ 2 ] ), val( pieces[ 3 ] ) );
			if ( dateFormat( parsed, "yyyy-mm-dd" ) != arguments.value ) return { success=false };
			return { success=true,value=parsed };
		} catch ( any ignored ) {
			return { success=false };
		}
	}

	private boolean function isCanonicalUuid( required string value ){
		return reFindNoCase(
			"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
			trim( arguments.value )
		) > 0;
	}

	private numeric function integerOrZero( any value = 0 ){
		if ( isNull( arguments.value ) || !isNumeric( arguments.value ) ) return 0;
		return round( val( arguments.value ) );
	}

	private struct function failure( required string code ){
		var result = {};
		result[ "found" ] = false;
		result[ "code" ] = arguments.code;
		return result;
	}

}
