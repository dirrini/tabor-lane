component {

    property name="boardService" inject="BoardService";

    this.allowedMethods = {
        index = "GET",
        createCard = "POST",
        moveCard = "POST"
    };

    function preHandler( event, rc, prc, action, eventArguments ) {
        if ( !structKeyExists( session, "auth" ) ) {
            relocate( uri = "/login" );
        }
        prc.auth = session.auth;
    }

    function index( event, rc, prc ) {
        prc.page = "app";
        prc.pageTitle = $r( "app.metaTitle" );
        prc.workspaceBoard = boardService.getWorkspaceBoard( prc.auth.id, prc.auth.workspaceId );
        prc.cardCsrfToken = csrfGenerateToken( "card-write" );
        prc.logoutCsrfToken = csrfGenerateToken( "logout" );
        event.setView( "app/index" );
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
            event.renderData( type = "json", data = { success = false, code = "csrf" }, statusCode = 403 );
            return;
        }
        var result = boardService.moveCard(
            userId = prc.auth.id,
            workspaceId = prc.auth.workspaceId,
            cardId = rc.cardId ?: "",
            columnId = rc.columnId ?: ""
        );
        event.renderData(
            type = "json",
            data = result,
            statusCode = result.success ? 200 : 403
        );
    }

}
