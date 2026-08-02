component {

	property name="automationService" inject="AutomationService";
	property name="authService" inject="AuthService";
	property name="workspaceViewService" inject="WorkspaceViewService";

	this.allowedMethods = {
		index="GET",
		create="POST",
		toggle="POST",
		remove="POST"
	};

	function preHandler( event, rc, prc, action, eventArguments ){
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

	function index( event, rc, prc ){
		prc.page = "automations";
		prc.pageTitle = $r( "automations.metaTitle" );
		prc.automationManagement = automationService.getManagement(
			prc.auth.id,
			prc.auth.workspaceId
		);
		if ( !prc.automationManagement.found ) relocate( uri="/app" );

		prc.automationCsrfToken = csrfGenerateToken( "automation-manage" );
		prc.logoutCsrfToken = csrfGenerateToken( "logout" );
		prc.notice = rc.notice ?: "";
		prc.error = rc.error ?: "";
		event.setHTTPHeader( name="Cache-Control", value="no-store" );

		if ( isAutomationPanelRequest() ) {
			prc.isHtmxRequest = true;
			event.setView( view="app/_automationPanel", noLayout=true );
			return;
		}
		workspaceViewService.render( event, prc, "app/automations" );
	}

	function create( event, rc, prc ){
		requireCsrf( rc );
		var destination = parseDestination( rc.destination ?: "" );
		var result = automationService.createRule(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			name=rc.name ?: "",
			boardId=destination.boardId,
			columnId=destination.columnId,
			recipientUserId=cleanId( rc.recipientUserId ?: "" )
		);
		finishWrite( result, "created" );
	}

	function toggle( event, rc, prc ){
		requireCsrf( rc );
		var enabled = listFindNoCase( "1,true,on,yes", rc.enabled ?: "false" ) > 0;
		var result = automationService.setEnabled(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			ruleId=cleanId( rc.ruleId ?: "" ),
			enabled=enabled
		);
		finishWrite( result, enabled ? "enabled" : "paused" );
	}

	function remove( event, rc, prc ){
		requireCsrf( rc );
		var result = automationService.removeRule(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			ruleId=cleanId( rc.ruleId ?: "" )
		);
		finishWrite( result, "removed" );
	}

	private void function requireCsrf( required struct rc ){
		if ( !csrfVerifyToken( arguments.rc.csrfToken ?: "", "automation-manage" ) ) {
			relocate( uri="/app/automations?error=expired" );
		}
	}

	private void function finishWrite( required struct result, required string notice ){
		if ( arguments.result.success ) {
			relocate( uri="/app/automations?notice=#urlEncodedFormat( arguments.notice )#" );
		}
		relocate(
			uri="/app/automations?error=#urlEncodedFormat( arguments.result.code ?: 'generic' )#"
		);
	}

	private boolean function isAutomationPanelRequest(){
		var headers = getHttpRequestData().headers ?: {};
		return compareNoCase( headers[ "HX-Request" ] ?: "", "true" ) == 0
			&& compareNoCase( headers[ "HX-Target" ] ?: "", "automation-panel" ) == 0
			&& compareNoCase( headers[ "HX-History-Restore-Request" ] ?: "", "true" ) != 0;
	}

	private string function cleanId( required string value ){
		var candidate = trim( urlDecode( arguments.value ) );
		return reFindNoCase(
			"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
			candidate
		) ? candidate : "";
	}

	private struct function parseDestination( required string value ){
		var parts = listToArray( urlDecode( trim( arguments.value ) ), ":" );
		if ( parts.len() != 2 ) return { boardId="",columnId="" };
		return { boardId=cleanId( parts[ 1 ] ),columnId=cleanId( parts[ 2 ] ) };
	}

}
