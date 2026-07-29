component {

    property name="boardService" inject="BoardService";
    property name="workspaceService" inject="WorkspaceService";
    property name="notificationService" inject="NotificationService";
    property name="rateLimitService" inject="RateLimitService";
    property name="authService" inject="AuthService";
    property name="workspaceViewService" inject="WorkspaceViewService";

    this.allowedMethods = {
        index = "GET",
        createCard = "POST",
        moveCard = "POST",
        members = "GET",
        inviteMember = "POST"
    };

    function preHandler( event, rc, prc, action, eventArguments ) {
        if ( !structKeyExists( session, "auth" ) ) {
            relocate( uri = "/login" );
        }
        session.auth.emailVerified = authService.isEmailVerified( session.auth.id );
        if ( !session.auth.emailVerified ) {
            relocate( uri = "/check-email" );
        }
        prc.auth = session.auth;
    }

    function members( event, rc, prc ) {
        prc.page = "members";
        prc.pageTitle = $r( "members.title" );
        prc.members = workspaceService.getMembers( prc.auth.id, prc.auth.workspaceId );
        prc.invitations = workspaceService.getPendingInvitations( prc.auth.id, prc.auth.workspaceId );
        prc.canInvite = listFindNoCase( "owner,admin", prc.auth.role ) > 0;
        prc.inviteCsrfToken = csrfGenerateToken( "invite-member" );
        prc.logoutCsrfToken = csrfGenerateToken( "logout" );
        prc.notice = rc.invited ?: "";
        prc.error = rc.error ?: "";
        prc.developmentInvitationToken = ( server.system.environment.APP_ENV ?: "development" ) != "production"
            ? session.developmentInvitationToken ?: ""
            : "";
        workspaceViewService.render( event, prc, "app/members" );
    }

    function inviteMember( event, rc, prc ) {
        if (
            !csrfVerifyToken( rc.csrfToken ?: "", "invite-member" )
            || !isValid( "email", trim( rc.email ?: "" ) )
        ) {
            relocate( uri = "/app/members?error=invalid" );
        }
        if ( !rateLimitService.allow( "invite:#prc.auth.id#", 20, 3600 ) ) {
            relocate( uri = "/app/members?error=rate" );
        }
        var result = workspaceService.createInvitation(
            userId = prc.auth.id,
            workspaceId = prc.auth.workspaceId,
            email = rc.email,
            role = rc.role ?: "member",
            locale = getFWLocale()
        );
        if ( !result.success ) {
            relocate( uri = "/app/members?error=#urlEncodedFormat( result.code )#" );
        }
        notificationService.sendWorkspaceInvitation( result );
        if ( ( server.system.environment.APP_ENV ?: "development" ) != "production" ) {
            session.developmentInvitationToken = result.token;
        }
        relocate( uri = "/app/members?invited=1" );
    }

    function index( event, rc, prc ) {
        prc.page = "app";
        prc.pageTitle = $r( "app.metaTitle" );
        prc.workspaceBoard = boardService.getWorkspaceBoard( prc.auth.id, prc.auth.workspaceId );
        prc.cardCsrfToken = csrfGenerateToken( "card-write" );
        prc.logoutCsrfToken = csrfGenerateToken( "logout" );
        workspaceViewService.render( event, prc, "app/index" );
    }

    function createCard( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "card-write" ) ) {
            relocate( uri = "/app" );
        }
        if ( trim( rc.title ?: "" ).len() && trim( rc.columnId ?: "" ).len() ) {
            boardService.createCard(
                userId = prc.auth.id,
                workspaceId = prc.auth.workspaceId,
                columnId = rc.columnId,
                title = rc.title,
                description = rc.description ?: ""
            );
        }
        relocate( uri = "/app" );
    }

    function moveCard( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "card-write" ) ) {
            var csrfResponse = structNew( "ordered" );
            csrfResponse[ "success" ] = false;
            csrfResponse[ "code" ] = "csrf";
            event.renderData( type = "json", data = csrfResponse, statusCode = 403 );
            return;
        }
        var result = boardService.moveCard(
            userId = prc.auth.id,
            workspaceId = prc.auth.workspaceId,
            cardId = rc.cardId ?: "",
            columnId = rc.columnId ?: ""
        );
        var responseData = structNew( "ordered" );
        responseData[ "success" ] = result.success;
        if ( structKeyExists( result, "code" ) ) {
            responseData[ "code" ] = result.code;
        }
        event.renderData(
            type = "json",
            data = responseData,
            statusCode = result.success ? 200 : 403
        );
    }

}
