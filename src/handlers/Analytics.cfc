component {

	property name="analyticsService" inject="AnalyticsService";
	property name="authService" inject="AuthService";
	property name="workspaceViewService" inject="WorkspaceViewService";

	this.allowedMethods = {
		index = "GET",
		metrics = "GET"
	};

	function preHandler( event, rc, prc, action, eventArguments ) {
		if ( !structKeyExists( session, "auth" ) ) relocate( uri="/login" );
		session.auth.emailVerified = authService.isEmailVerified( session.auth.id );
		if ( !session.auth.emailVerified ) relocate( uri="/check-email" );
		var workspaceContext = authService.resolveWorkspaceContext(
			session.auth.id,
			session.auth.workspaceId ?: ""
		);
		if ( !workspaceContext.found ) {
			sessionInvalidate();
			relocate( uri="/login" );
		}
		session.auth.workspaceId = workspaceContext.workspaceId;
		session.auth.workspaceName = workspaceContext.workspaceName;
		session.auth.role = workspaceContext.role;
		prc.auth = session.auth;
		prc.workspaceSwitchCsrfToken = csrfGenerateToken( "workspace-select" );
	}

	function index( event, rc, prc ) {
		prc.page = "analytics";
		prc.pageTitle = $r( "analytics.metaTitle" );
		prc.analyticsError = "";
		var isResultsPartial = isAnalyticsResultsRequest();

		var requestedFilters = {};
		requestedFilters[ "fromDate" ] = rc.fromDate ?: "";
		requestedFilters[ "toDate" ] = rc.toDate ?: "";
		requestedFilters[ "boardId" ] = rc.boardId ?: "";
		requestedFilters[ "assigneeId" ] = rc.assigneeId ?: "";

		prc.analytics = analyticsService.getDashboard(
			prc.auth.id,
			prc.auth.workspaceId,
			requestedFilters
		);
		if ( !prc.analytics.found ) {
			prc.analyticsError = expectedPageError( prc.analytics.code ?: "" );
			prc.analytics = analyticsService.getDashboard(
				prc.auth.id,
				prc.auth.workspaceId,
				{}
			);
			if ( !prc.analytics.found ) relocate( uri="/app" );
		}

		event.setHTTPHeader( name="Cache-Control", value="no-store" );
		if ( isResultsPartial ) {
			prc.isHtmxRequest = true;
			event.setView( view="app/_analyticsResults", noLayout=true );
			return;
		}

		prc.analyticsOptions = analyticsService.getFilterOptions(
			prc.auth.id,
			prc.auth.workspaceId
		);
		if ( !prc.analyticsOptions.found ) relocate( uri="/app" );

		prc.analyticsFilters = {};
		prc.analyticsFilters[ "fromDate" ] = prc.analytics.period.from;
		prc.analyticsFilters[ "toDate" ] = prc.analytics.period.to;
		prc.analyticsFilters[ "boardId" ] = prc.analytics.filters.boardId;
		prc.analyticsFilters[ "assigneeId" ] = prc.analytics.filters.assigneeId;
		prc.logoutCsrfToken = csrfGenerateToken( "logout" );

		workspaceViewService.render( event, prc, "app/analytics" );
	}

	function metrics( event, rc, prc ) {
		var result = analyticsService.getDashboard(
			prc.auth.id,
			prc.auth.workspaceId,
			{
				fromDate = rc.fromDate ?: "",
				toDate = rc.toDate ?: "",
				boardId = rc.boardId ?: "",
				assigneeId = rc.assigneeId ?: ""
			}
		);
		var resultCode = lCase( result.code ?: "" );
		var statusCode = 200;

		if ( listFindNoCase( "invalid_filter,invalid_period", resultCode ) ) {
			statusCode = 422;
		} else if ( resultCode == "forbidden" ) {
			statusCode = 403;
		} else if ( resultCode == "not_found" || ( structKeyExists( result, "found" ) && !result.found ) ) {
			statusCode = 404;
		}

		event.setHTTPHeader( name = "Cache-Control", value = "no-store" );
		event.renderData(
			type = "json",
			data = result,
			statusCode = statusCode
		);
	}

	private string function expectedPageError( required string code ) {
		var normalizedCode = lCase( trim( arguments.code ) );
		return listFindNoCase(
			"invalid_filter,invalid_period,not_found,forbidden",
			normalizedCode
		) ? normalizedCode : "generic";
	}

	private boolean function isAnalyticsResultsRequest() {
		var headers = getHttpRequestData().headers ?: {};
		return compareNoCase( headers[ "HX-Request" ] ?: "", "true" ) == 0
			&& compareNoCase( headers[ "HX-Target" ] ?: "", "analytics-results" ) == 0
			&& compareNoCase( headers[ "HX-History-Restore-Request" ] ?: "", "true" ) != 0;
	}

}
