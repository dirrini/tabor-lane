component {

	property name="analyticsService" inject="AnalyticsService";
	property name="authService" inject="AuthService";

	this.allowedMethods = {
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

}
