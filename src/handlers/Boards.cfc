component {

    property name="boardManagementService" inject="BoardManagementService";
    property name="authService" inject="AuthService";
    property name="workspaceViewService" inject="WorkspaceViewService";

    this.allowedMethods={
        index="GET",
        create="POST",
        update="POST",
        archive="POST",
        restore="POST",
        moveBoard="POST",
        createLane="POST",
        updateLane="POST",
        deleteLane="POST",
        moveLane="POST"
    };

    function preHandler(event,rc,prc,action,eventArguments){
        if(!structKeyExists(session,"auth")) relocate(uri="/login");
        session.auth.emailVerified=authService.isEmailVerified(session.auth.id);
        if(!session.auth.emailVerified) relocate(uri="/check-email");
        prc.auth=session.auth;
    }

    function index(event,rc,prc){
        prc.page="app";
        prc.pageTitle=$r("boards.title");
        prc.management=boardManagementService.getManagement(
            prc.auth.id,prc.auth.workspaceId,cleanId(rc.boardId ?: "")
        );
        if(!prc.management.found) relocate(uri="/app");
        prc.boardCsrfToken=csrfGenerateToken("board-manage");
        prc.logoutCsrfToken=csrfGenerateToken("logout");
        prc.notice=rc.notice ?: "";
        prc.error=rc.error ?: "";
        workspaceViewService.render(event,prc,"app/boards");
    }

    function create(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.createBoard(
            userId=prc.auth.id,workspaceId=prc.auth.workspaceId,
            name=rc.name ?: "",description=rc.description ?: "",
            template=rc.template ?: "blank",locale=getFWLocale()
        );
        finish(result,"created");
    }

    function update(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.updateBoard(
            prc.auth.id,prc.auth.workspaceId,cleanId(rc.boardId ?: ""),
            rc.name ?: "",rc.description ?: ""
        );
        finish(result,"saved",rc.boardId ?: "");
    }

    function archive(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.archiveBoard(
            prc.auth.id,prc.auth.workspaceId,cleanId(rc.boardId ?: "")
        );
        finish(result,"archived");
    }

    function restore(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.restoreBoard(
            prc.auth.id,prc.auth.workspaceId,cleanId(rc.boardId ?: "")
        );
        finish(result,"restored",rc.boardId ?: "");
    }

    function moveBoard(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.moveBoard(
            prc.auth.id,prc.auth.workspaceId,cleanId(rc.boardId ?: ""),rc.direction ?: ""
        );
        finish(result,"board_moved",rc.boardId ?: "");
    }

    function createLane(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.createLane(
            userId=prc.auth.id,workspaceId=prc.auth.workspaceId,
            boardId=cleanId(rc.boardId ?: ""),name=rc.name ?: "",
            color=rc.color ?: "red",wipLimit=rc.wipLimit ?: ""
        );
        finish(result,"lane_created",rc.boardId ?: "");
    }

    function updateLane(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.updateLane(
            userId=prc.auth.id,workspaceId=prc.auth.workspaceId,
            boardId=cleanId(rc.boardId ?: ""),laneId=cleanId(rc.laneId ?: ""),
            name=rc.name ?: "",color=rc.color ?: "red",wipLimit=rc.wipLimit ?: ""
        );
        finish(result,"lane_saved",rc.boardId ?: "");
    }

    function deleteLane(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.deleteLane(
            prc.auth.id,prc.auth.workspaceId,cleanId(rc.boardId ?: ""),cleanId(rc.laneId ?: "")
        );
        finish(result,"lane_deleted",rc.boardId ?: "");
    }

    function moveLane(event,rc,prc){
        requireCsrf(rc);
        var result=boardManagementService.moveLane(
            prc.auth.id,prc.auth.workspaceId,cleanId(rc.boardId ?: ""),
            cleanId(rc.laneId ?: ""),rc.direction ?: ""
        );
        finish(result,"lane_moved",rc.boardId ?: "");
    }

    private void function requireCsrf(required struct rc){
        if(!csrfVerifyToken(arguments.rc.csrfToken ?: "","board-manage"))
            relocate(uri="/app/boards/manage?error=expired");
    }

    private void function finish(required struct result,required string notice,string fallbackBoardId=""){
        var selected=arguments.result.boardId ?: cleanId(arguments.fallbackBoardId);
        var boardQuery=selected.len()?"&boardId=#urlEncodedFormat(selected)#":"";
        if(arguments.result.success){
            relocate(uri="/app/boards/manage?notice=#urlEncodedFormat(arguments.notice)#" & boardQuery);
        }
        relocate(
            uri="/app/boards/manage?error=#urlEncodedFormat(arguments.result.code ?: 'generic')#" & boardQuery
        );
    }

    private string function cleanId(required string value){
        var candidate=trim(urlDecode(arguments.value));
        return reFindNoCase("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",candidate)
            ? candidate : "";
    }
}
