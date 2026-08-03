component {

	property name="integrationService" inject="IntegrationService";
	property name="authService" inject="AuthService";
	property name="rateLimitService" inject="RateLimitService";
	property name="workspaceViewService" inject="WorkspaceViewService";

	this.allowedMethods = {
		index="GET",
		createToken="POST",
		revokeToken="POST",
		createWebhook="POST",
		toggleWebhook="POST",
		deleteWebhook="POST",
		testWebhook="POST"
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
		prc.page = "integrations";
		prc.pageTitle = $r( "integrations.metaTitle" );
		prc.integrations = integrationService.getDashboard(
			prc.auth.id,
			prc.auth.workspaceId
		);
		if ( !prc.integrations.found ) relocate( uri="/app/settings" );

		prc.integrationsCsrfToken = csrfGenerateToken( "workspace-integrations" );
		prc.logoutCsrfToken = csrfGenerateToken( "logout" );
		prc.notice = expectedNotice( rc.notice ?: "" );
		prc.error = trim( rc.error ?: "" ).len() ? expectedError( rc.error ) : "";
		prc.integrationReveal = {};
		if ( structKeyExists( session, "integrationReveal" ) ) {
			prc.integrationReveal = duplicate( session.integrationReveal );
			structDelete( session, "integrationReveal" );
		}
		event.setHTTPHeader( name="Cache-Control", value="no-store" );
		workspaceViewService.render( event, prc, "app/integrations" );
	}

	function createToken( event, rc, prc ){
		requireCsrf( rc );
		if ( !rateLimitService.allow( "integration-token-create:#prc.auth.id#", 10, 3600 ) ) {
			finish( { success=false,code="rate" }, "token_created" );
		}
		var result = integrationService.createToken(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			name=rc.name ?: "",
			scopes=rc.scopes ?: "",
			expirationDays=rc.expirationDays ?: "90"
		);
		if ( result.success ) {
			session.integrationReveal = {
				kind="token",
				value=result.token,
				name=result.name ?: trim( rc.name ?: "" )
			};
		}
		finish( result, "token_created" );
	}

	function revokeToken( event, rc, prc ){
		requireCsrf( rc );
		finish(
			integrationService.revokeToken(
				userId=prc.auth.id,
				workspaceId=prc.auth.workspaceId,
				tokenId=rc.tokenId ?: ""
			),
			"token_revoked"
		);
	}

	function createWebhook( event, rc, prc ){
		requireCsrf( rc );
		if ( !rateLimitService.allow( "integration-webhook-create:#prc.auth.id#", 10, 3600 ) ) {
			finish( { success=false,code="rate" }, "webhook_created" );
		}
		var result = integrationService.createEndpoint(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			name=rc.name ?: "",
			url=rc.endpointUrl ?: "",
			eventTypes=rc.eventTypes ?: ""
		);
		if ( result.success ) {
			session.integrationReveal = {
				kind="webhook",
				value=result.secret,
				name=result.name ?: trim( rc.name ?: "" )
			};
		}
		finish( result, "webhook_created" );
	}

	function toggleWebhook( event, rc, prc ){
		requireCsrf( rc );
		var shouldEnable = isTruthy( rc.enabled ?: "" );
		var result = integrationService.toggleEndpoint(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			endpointId=rc.endpointId ?: "",
			enabled=shouldEnable
		);
		finish( result, shouldEnable ? "webhook_enabled" : "webhook_disabled" );
	}

	function deleteWebhook( event, rc, prc ){
		requireCsrf( rc );
		finish(
			integrationService.deleteEndpoint(
				userId=prc.auth.id,
				workspaceId=prc.auth.workspaceId,
				endpointId=rc.endpointId ?: ""
			),
			"webhook_deleted"
		);
	}

	function testWebhook( event, rc, prc ){
		requireCsrf( rc );
		if ( !rateLimitService.allow( "integration-webhook-test:#prc.auth.id#", 20, 3600 ) ) {
			finish( { success=false,code="rate" }, "webhook_test_queued" );
		}
		finish(
			integrationService.queueTestEndpoint(
				userId=prc.auth.id,
				workspaceId=prc.auth.workspaceId,
				endpointId=rc.endpointId ?: ""
			),
			"webhook_test_queued"
		);
	}

	private void function requireCsrf( required struct rc ){
		if ( !csrfVerifyToken( arguments.rc.csrfToken ?: "", "workspace-integrations" ) ) {
			relocate( uri="/app/settings/integrations?error=expired" );
		}
	}

	private void function finish( required struct result, required string notice ){
		if ( arguments.result.success ) {
			relocate( uri="/app/settings/integrations?notice=#urlEncodedFormat( arguments.notice )#" );
		}
		relocate(
			uri="/app/settings/integrations?error=#urlEncodedFormat( expectedError( arguments.result.code ?: 'generic' ) )#"
		);
	}

	private string function expectedNotice( required string value ){
		var normalized = lCase( trim( arguments.value ) );
		return listFindNoCase(
			"token_created,token_revoked,webhook_created,webhook_enabled,webhook_disabled,webhook_deleted,webhook_test_queued",
			normalized
		) ? normalized : "";
	}

	private string function expectedError( required string value ){
		var normalized = lCase( trim( arguments.value ) );
		return listFindNoCase(
			"expired,invalid,forbidden,not_found,limit_reached,scope_required,invalid_url,key_not_configured,rate,generic",
			normalized
		) ? normalized : "generic";
	}

	private boolean function isTruthy( required any value ){
		return listFindNoCase( "1,true,yes,on", lCase( trim( toString( arguments.value ) ) ) ) > 0;
	}

}
