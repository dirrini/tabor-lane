component {

    property name="boardService" inject="BoardService";
    property name="workspaceService" inject="WorkspaceService";
    property name="notificationService" inject="NotificationService";
    property name="rateLimitService" inject="RateLimitService";
    property name="authService" inject="AuthService";
    property name="workspaceViewService" inject="WorkspaceViewService";
    property name="attachmentService" inject="AttachmentService";

    this.allowedMethods = {
        index = "GET",
        createCard = "POST",
        moveCard = "POST",
        updateLaneLayout = "POST",
        cardDetails = "GET",
        updateCard = "POST",
        addCardComment = "POST",
        archiveCard = "POST",
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
            || !trim( rc.inviteeName ?: "" ).len()
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
            inviteeName = rc.inviteeName,
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
        prc.workspaceBoard = boardService.getWorkspaceBoard(
            prc.auth.id,
            prc.auth.workspaceId,
            rc.boardId ?: ""
        );
        prc.cardCsrfToken = csrfGenerateToken( "card-write" );
        prc.logoutCsrfToken = csrfGenerateToken( "logout" );
        workspaceViewService.render( event, prc, "app/index" );
    }

    function createCard( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "card-write" ) ) {
            relocate( uri = "/app" );
        }
        if ( trim( rc.title ?: "" ).len() && trim( rc.columnId ?: "" ).len() ) {
            var result=boardService.createCard(
                userId = prc.auth.id,
                workspaceId = prc.auth.workspaceId,
                columnId = rc.columnId,
                title = rc.title,
                description = rc.description ?: ""
            );
            if(result.success) relocate(uri="/app?boardId=#urlEncodedFormat(result.boardId)#");
        }
        relocate( uri = "/app" );
    }

    function cardDetails( event, rc, prc ) {
        prc.page = "app";
        prc.cardDetails = boardService.getCardDetails( prc.auth.id, prc.auth.workspaceId, rc.cardId ?: "" );
        if ( !prc.cardDetails.found ) relocate( uri="/app" );
        prc.pageTitle = prc.cardDetails.card.title;
        prc.cardCsrfToken = csrfGenerateToken( "card-write" );
        prc.attachments = attachmentService.getForCard(
            userId=prc.auth.id,
            workspaceId=prc.auth.workspaceId,
            cardId=rc.cardId
        );
        prc.logoutCsrfToken = csrfGenerateToken( "logout" );
        prc.canEditCard = prc.cardDetails.card.access_role != "viewer";
        prc.notice = ( rc.attachmentRemoved ?: "" ) == "1"
            ? "attachmentRemoved"
            : ( rc.attached ?: "" ) == "1" ? "attached"
            : ( rc.updated ?: "" ) == "1"
            ? "saved"
            : ( rc.commented ?: "" ) == "1" ? "commented" : "";
        prc.error = rc.error ?: "";
        workspaceViewService.render( event, prc, "app/card" );
    }

    function updateCard( event, rc, prc ) {
        if (
            !csrfVerifyToken( rc.csrfToken ?: "", "card-write" )
            || !trim( rc.title ?: "" ).len()
            || trim( rc.title ?: "" ).len() > 255
            || ( trim( rc.dueDate ?: "" ).len() && !isValid( "date", rc.dueDate ) )
        ) {
            relocate( uri="/app/cards/#rc.cardId#?error=invalid" );
        }
        var result = boardService.updateCard( prc.auth.id, prc.auth.workspaceId, rc.cardId, rc );
        var redirectQuery = result.success
            ? "updated=1"
            : "error=" & urlEncodedFormat( result.code ?: "generic" );
        relocate( uri="/app/cards/#rc.cardId#?#redirectQuery#" );
    }

    function addCardComment( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "card-write" ) ) {
            relocate( uri="/app/cards/#rc.cardId#?error=expired" );
        }
        var result = boardService.addComment( prc.auth.id, prc.auth.workspaceId, rc.cardId, rc.body ?: "" );
        var redirectQuery = result.success
            ? "commented=1"
            : "error=" & urlEncodedFormat( result.code ?: "generic" );
        relocate( uri="/app/cards/#rc.cardId#?#redirectQuery#" );
    }

    function archiveCard( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "card-write" ) ) {
            relocate( uri="/app/cards/#rc.cardId#?error=expired" );
        }
        var result = boardService.archiveCard( prc.auth.id, prc.auth.workspaceId, rc.cardId );
        var boardQuery=result.boardId ?: "";
        relocate( uri=result.success ? "/app?boardId=#urlEncodedFormat(boardQuery)#&cardArchived=1" : "/app/cards/#rc.cardId#?error=#urlEncodedFormat( result.code ?: "generic" )#" );
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
            columnId = rc.columnId ?: "",
            beforeCardId = rc.beforeCardId ?: ""
        );
        var responseData = structNew( "ordered" );
        responseData[ "success" ] = result.success;
        if ( structKeyExists( result, "code" ) ) {
            responseData[ "code" ] = result.code;
        }
        event.renderData(
            type = "json",
            data = responseData,
            statusCode = result.success ? 200 : ( result.code ?: "" ) == "wip_limit" ? 409 : 403
        );
    }

    function updateLaneLayout( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "card-write" ) ) {
            event.renderData( type="json", data={ success=false, code="csrf" }, statusCode=403 );
            return;
        }
        var result = boardService.saveLanePreference(
            userId=prc.auth.id,
            workspaceId=prc.auth.workspaceId,
            columnId=rc.laneId ?: "",
            widthPx=isNumeric( rc.widthPx ?: "" ) ? val( rc.widthPx ) : 280,
            isCollapsed=( rc.isCollapsed ?: "false" ) == "true"
        );
        var responseData=structNew("ordered");
        responseData["success"]=result.success;
        if(result.success){
            responseData["widthPx"]=result.widthPx;
            responseData["isCollapsed"]=result.isCollapsed;
        } else {
            responseData["code"]=result.code ?: "forbidden";
        }
        event.renderData(
            type="json",
            data=responseData,
            statusCode=result.success ? 200 : 403
        );
    }

}
