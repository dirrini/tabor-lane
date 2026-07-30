component {

	property name="myWorkService" inject="MyWorkService";
	property name="authService" inject="AuthService";
	property name="workspaceViewService" inject="WorkspaceViewService";

	this.allowedMethods = {
		index = "GET",
		updateCard = "POST"
	};

	function preHandler( event, rc, prc, action, eventArguments ) {
		if ( !structKeyExists( session, "auth" ) ) relocate( uri="/login" );
		session.auth.emailVerified = authService.isEmailVerified( session.auth.id );
		if ( !session.auth.emailVerified ) relocate( uri="/check-email" );
		prc.auth = session.auth;
	}

	function index( event, rc, prc ) {
		prc.page = "myWork";
		prc.pageTitle = $r( "myWork.metaTitle" );
		prc.myWork = loadDashboard( prc.auth, rc );
		prc.myWorkCsrfToken = csrfGenerateToken( "my-work-write" );
		prc.logoutCsrfToken = csrfGenerateToken( "logout" );
		prc.notice = ( rc.saved ?: "" ) == "1" ? "saved" : "";
		prc.error = rc.error ?: "";
		workspaceViewService.render( event, prc, "app/myWork" );
	}

	function updateCard( event, rc, prc ) {
		if ( !csrfVerifyToken( rc.csrfToken ?: "", "my-work-write" ) ) {
			event.renderData( type="json", data={ success=false, code="csrf" }, statusCode=403 );
			return;
		}
		var validRequest =
			reFindNoCase( "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", rc.cardId ?: "" )
			&& reFind( "^[0-9]+$", toString( rc.version ?: "" ) )
			&& listFindNoCase( "none,low,medium,high,urgent", rc.priority ?: "" )
			&& (
				!trim( rc.dueDate ?: "" ).len()
				|| ( reFind( "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", rc.dueDate ) && isValid( "date", rc.dueDate ) )
			);
		var result = validRequest
			? myWorkService.updateCardFocus(
				userId=prc.auth.id,
				workspaceId=prc.auth.workspaceId,
				cardId=rc.cardId,
				priority=rc.priority,
				dueDate=rc.dueDate ?: "",
				version=rc.version
			)
			: { success=false, code="invalid" };

		if ( isHtmxRequest() ) {
			prc.myWork = loadDashboard( prc.auth, rc );
			prc.myWorkCsrfToken = csrfGenerateToken( "my-work-write" );
			prc.notice = result.success ? "saved" : "";
			prc.error = result.success ? "" : ( result.code ?: "generic" );
			event.setView( view="app/_myWorkResults", noLayout=true );
			return;
		}
		relocate( uri=result.success ? "/app/my-work?saved=1" : "/app/my-work?error=#urlEncodedFormat( result.code ?: 'generic' )#" );
	}

	private struct function loadDashboard( required struct auth, required struct requestCollection ) {
		return myWorkService.getDashboard(
			userId=arguments.auth.id,
			workspaceId=arguments.auth.workspaceId,
			requestedFilters={
				query=arguments.requestCollection.query ?: "",
				boardId=arguments.requestCollection.boardId ?: "",
				priority=arguments.requestCollection.filterPriority ?: ( arguments.requestCollection.priority ?: "" ),
				due=arguments.requestCollection.due ?: "all",
				sort=arguments.requestCollection.sort ?: "due"
			}
		);
	}

	private boolean function isHtmxRequest() {
		var headers = getHttpRequestData().headers ?: {};
		return compareNoCase( headers[ "HX-Request" ] ?: "", "true" ) == 0;
	}

}
