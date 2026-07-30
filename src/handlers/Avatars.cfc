component {

    property name="avatarService" inject="AvatarService";
    property name="authService" inject="AuthService";
    property name="rateLimitService" inject="RateLimitService";

    this.allowedMethods = {
        presign = "POST",
        complete = "POST",
        remove = "POST",
        image = "GET"
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
    }

    function presign( event, rc, prc ){
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "profile-avatar" ) ) {
            return json( event, { success=false, code="csrf" }, 403 );
        }
        if ( !rateLimitService.allow( "profile-avatar:#prc.auth.id#", 10, 3600 ) ) {
            return json( event, { success=false, code="rate" }, 429 );
        }
        var result = avatarService.initiate(
            userId=prc.auth.id,
            filename=rc.filename ?: "",
            sourceContentType=rc.sourceContentType ?: "",
            sourceSize=val( rc.sourceSize ?: 0 ),
            outputSize=val( rc.outputSize ?: 0 )
        );
        return json( event, result, result.success ? 200 : 422 );
    }

    function complete( event, rc, prc ){
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "profile-avatar" ) ) {
            return json( event, { success=false, code="csrf" }, 403 );
        }
        if ( !validUuid( rc.avatarId ?: "" ) ) {
            return json( event, { success=false, code="invalid" }, 422 );
        }
        var result = avatarService.complete( prc.auth.id, rc.avatarId );
        return json( event, result, result.success ? 200 : 422 );
    }

    function remove( event, rc, prc ){
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "profile-avatar" ) ) {
            return json( event, { success=false, code="csrf" }, 403 );
        }
        return json( event, avatarService.remove( prc.auth.id ), 200 );
    }

    function image( event, rc, prc ){
        if ( !validUuid( rc.userId ?: "" ) ) {
            event.renderData( type="text", data="", statusCode=404 );
            return;
        }
        var result = avatarService.getDownload(
            requesterId=prc.auth.id,
            workspaceId=prc.auth.workspaceId,
            targetUserId=rc.userId
        );
        if ( !result.success ) {
            event.renderData( type="text", data="", statusCode=404 );
            return;
        }
        relocate( uri=result.url );
    }

    private boolean function validUuid( required string value ){
        return reFindNoCase(
            "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            arguments.value
        ) > 0;
    }

    private any function json(
        required any event,
        required struct result,
        required numeric statusCode
    ){
        var payload = structNew( "ordered" );
        for ( var key in [ "success", "code", "id", "uploadUrl", "url" ] ) {
            if ( structKeyExists( arguments.result, key ) ) payload[ key ] = arguments.result[ key ];
        }
        if ( !structKeyExists( payload, "success" ) ) payload[ "success" ] = false;
        return arguments.event.renderData(
            type="json",
            data=payload,
            statusCode=arguments.statusCode
        );
    }

}
