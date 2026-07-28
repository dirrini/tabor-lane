component {

    property name="workspaceService" inject="WorkspaceService";

    this.allowedMethods = { accept = "GET" };

    function accept( event, rc, prc ) {
        prc.page = "invitation";
        prc.invitationToken = rc.token ?: "";
        prc.invitation = workspaceService.inspectInvitation( prc.invitationToken );
        prc.pageTitle = $r( "invite.title" );

        if ( prc.invitation.found && structKeyExists( session, "auth" ) ) {
            var result = workspaceService.acceptInvitation(
                token = prc.invitationToken,
                userId = session.auth.id,
                userEmail = session.auth.email
            );
            if ( result.success ) {
                session.auth.workspaceId = result.workspaceId;
                session.auth.workspaceName = result.workspaceName;
                session.auth.role = result.role;
                relocate( uri = "/app/members" );
            }
            prc.wrongAccount = true;
        } else {
            prc.wrongAccount = false;
        }
        event.setView( "auth/invitation" );
    }

}
