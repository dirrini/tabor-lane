component {

    property name="attachmentService" inject="AttachmentService";
    property name="authService" inject="AuthService";

    this.allowedMethods = {
        presign = "POST",
        complete = "POST",
        download = "GET",
        remove = "POST"
    };

    function preHandler( event, rc, prc, action, eventArguments ){
        if(!structKeyExists(session,"auth")) relocate(uri="/login");
        session.auth.emailVerified=authService.isEmailVerified(session.auth.id);
        if(!session.auth.emailVerified) relocate(uri="/check-email");
        var workspaceContext=authService.resolveWorkspaceContext(
            session.auth.id,session.auth.workspaceId ?: ""
        );
        if(!workspaceContext.found){
            sessionInvalidate();
            relocate(uri="/login");
        }
        session.auth.workspaceId=workspaceContext.workspaceId;
        session.auth.workspaceName=workspaceContext.workspaceName;
        session.auth.role=workspaceContext.role;
        prc.auth=session.auth;
    }

    function presign( event, rc, prc ){
        if(!csrfVerifyToken(rc.csrfToken ?: "","card-write")){
            return json(event,{success=false,code="csrf"},403);
        }
        var result=attachmentService.initiate(
            userId=prc.auth.id,
            workspaceId=prc.auth.workspaceId,
            cardId=rc.cardId ?: "",
            filename=rc.filename ?: "",
            contentType=rc.contentType ?: "application/octet-stream",
            size=val(rc.size ?: 0)
        );
        return json(event,result,result.success?200:422);
    }

    function complete( event, rc, prc ){
        if(!csrfVerifyToken(rc.csrfToken ?: "","card-write")){
            return json(event,{success=false,code="csrf"},403);
        }
        var result=attachmentService.complete(
            prc.auth.id,prc.auth.workspaceId,rc.cardId ?: "",rc.attachmentId ?: ""
        );
        return json(event,result,result.success?200:422);
    }

    function download( event, rc, prc ){
        var result=attachmentService.getDownload(prc.auth.id,prc.auth.workspaceId,rc.attachmentId ?: "");
        if(!result.success) relocate(uri="/app");
        relocate(uri=result.url);
    }

    function remove( event, rc, prc ){
        if(!csrfVerifyToken(rc.csrfToken ?: "","card-write")){
            relocate(uri="/app/cards/#rc.cardId#?error=expired");
        }
        var result=attachmentService.remove(
            prc.auth.id,prc.auth.workspaceId,rc.cardId ?: "",rc.attachmentId ?: ""
        );
        var redirectQuery=result.success?"attachmentRemoved=1":"error=attachment_storage";
        relocate(uri="/app/cards/#rc.cardId#?#redirectQuery#");
    }

    private any function json(required any event,required struct result,required numeric statusCode){
        var payload=structNew("ordered");
        payload["success"]=arguments.result.success ?: false;
        if(structKeyExists(arguments.result,"code")) payload["code"]=arguments.result.code;
        if(structKeyExists(arguments.result,"id")) payload["id"]=arguments.result.id;
        if(structKeyExists(arguments.result,"uploadUrl")) payload["uploadUrl"]=arguments.result.uploadUrl;
        return arguments.event.renderData(type="json",data=payload,statusCode=arguments.statusCode);
    }
}
