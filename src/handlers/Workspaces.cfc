component {

    property name="workspaceService" inject="WorkspaceService";
    property name="authService" inject="AuthService";

    this.allowedMethods = { select = "POST" };

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
    }

    function select( event, rc, prc ){
        if (
            !csrfVerifyToken( rc.csrfToken ?: "", "workspace-select" )
            || !reFindNoCase(
                "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
                rc.workspaceId ?: ""
            )
        ) {
            relocate( uri="/app?workspaceError=invalid" );
        }
        var result = workspaceService.activateWorkspace( prc.auth.id, rc.workspaceId );
        if ( !result.success ) relocate( uri="/app?workspaceError=forbidden" );
        session.auth.workspaceId = result.workspaceId;
        session.auth.workspaceName = result.workspaceName;
        session.auth.role = result.role;
        relocate( uri="/app/my-work" );
    }

}
