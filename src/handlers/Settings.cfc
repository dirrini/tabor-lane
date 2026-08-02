component {

	property name="workspaceSettingsService" inject="WorkspaceSettingsService";
	property name="authService" inject="AuthService";
	property name="rateLimitService" inject="RateLimitService";
	property name="workspaceViewService" inject="WorkspaceViewService";

	this.allowedMethods = {
		index="GET",
		updateGeneral="POST",
		updateSecurity="POST",
		transferOwnership="POST"
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
		prc.page = "settings";
		prc.pageTitle = $r( "settings.metaTitle" );
		prc.workspaceSettings = workspaceSettingsService.getSettings(
			prc.auth.id,
			prc.auth.workspaceId
		);
		if ( !prc.workspaceSettings.found ) relocate( uri="/app" );

		prc.settingsCsrfToken = csrfGenerateToken( "workspace-settings" );
		prc.ownershipCsrfToken = csrfGenerateToken( "workspace-ownership" );
		prc.logoutCsrfToken = csrfGenerateToken( "logout" );
		prc.notice = expectedNotice( rc.notice ?: "" );
		prc.error = trim( rc.error ?: "" ).len() ? expectedError( rc.error ) : "";
		event.setHTTPHeader( name="Cache-Control", value="no-store" );
		workspaceViewService.render( event, prc, "app/settings" );
	}

	function updateGeneral( event, rc, prc ){
		requireCsrf( rc, "workspace-settings" );
		var result = workspaceSettingsService.updateGeneral(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			name=rc.name ?: "",
			slug=rc.slug ?: "",
			timezone=rc.timezone ?: "",
			defaultLocale=rc.defaultLocale ?: ""
		);
		finish( result, "general_saved" );
	}

	function updateSecurity( event, rc, prc ){
		requireCsrf( rc, "workspace-settings" );
		var result = workspaceSettingsService.updateSecurity(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			invitationPolicy=rc.invitationPolicy ?: "",
			boardCreationPolicy=rc.boardCreationPolicy ?: ""
		);
		finish( result, "security_saved" );
	}

	function transferOwnership( event, rc, prc ){
		requireCsrf( rc, "workspace-ownership" );
		if ( !rateLimitService.allow( "ownership-transfer:#prc.auth.id#", 5, 3600 ) ) {
			relocate( uri="/app/settings?error=rate" );
		}
		var result = workspaceSettingsService.transferOwnership(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			targetUserId=trim( urlDecode( rc.targetUserId ?: "" ) ),
			currentPassword=rc.currentPassword ?: ""
		);
		finish( result, "ownership_transferred" );
	}

	private void function requireCsrf( required struct rc, required string purpose ){
		if ( !csrfVerifyToken( arguments.rc.csrfToken ?: "", arguments.purpose ) ) {
			relocate( uri="/app/settings?error=expired" );
		}
	}

	private void function finish( required struct result, required string notice ){
		if ( arguments.result.success ) {
			relocate( uri="/app/settings?notice=#urlEncodedFormat( arguments.notice )#" );
		}
		relocate(
			uri="/app/settings?error=#urlEncodedFormat( expectedError( arguments.result.code ?: 'generic' ) )#"
		);
	}

	private string function expectedNotice( required string value ){
		var normalized = lCase( trim( arguments.value ) );
		return listFindNoCase(
			"general_saved,security_saved,ownership_transferred",
			normalized
		) ? normalized : "";
	}

	private string function expectedError( required string value ){
		var normalized = lCase( trim( arguments.value ) );
		return listFindNoCase(
			"expired,invalid,slug_taken,forbidden,invalid_target,password_required,invalid_password,rate,generic",
			normalized
		) ? normalized : "generic";
	}

}
