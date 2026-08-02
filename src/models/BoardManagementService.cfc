component singleton {

    struct function getManagement(
        required string userId,
        required string workspaceId,
        string boardId = ""
    ){
        var access = workspaceAccess( arguments.userId, arguments.workspaceId );
        if ( !access.found ) return { found=false };
        var canManageBoards = listFindNoCase( "owner,admin", access.role ) > 0;
        var canCreateByPolicy = canCreateBoards( access );

        var boards = queryExecute(
            "SELECT CAST(b.id AS TEXT) id,b.name,b.description,b.is_archived,b.created_at,b.position,
                    COUNT(c.id) FILTER (
                        WHERE c.archived_at IS NULL
                          AND (card_lane.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
                    ) active_card_count
             FROM board b
             LEFT JOIN card c ON c.board_id=b.id
             LEFT JOIN board_column card_lane
               ON card_lane.id=c.column_id
              AND card_lane.board_id=b.id
             WHERE b.workspace_id=CAST(:workspace AS UUID)
             GROUP BY b.id ORDER BY b.is_archived,b.position,b.created_at,b.name",
            {workspace=arguments.workspaceId,canViewHidden=canManageBoards},{returntype="array"}
        );
        var activeBoards=[];
        var archivedBoards=[];
        for(var board in boards){
            if(board.is_archived) archivedBoards.append(board); else activeBoards.append(board);
        }
        var selected={};
        for(var candidate in boards){
            if(candidate.id==arguments.boardId){ selected=candidate; break; }
        }
        if(!selected.count() && activeBoards.len()) selected=activeBoards[1];
        if(!selected.count() && archivedBoards.len()) selected=archivedBoards[1];

        var lanes=[];
        if(selected.count()){
            lanes=queryExecute(
                "SELECT CAST(bc.id AS TEXT) id,bc.name,bc.position,bc.wip_limit,bc.color,
                        bc.is_hidden_from_members,bc.is_completion_lane,
                        COUNT(c.id) card_count,
                        COUNT(c.id) FILTER (WHERE c.archived_at IS NULL) active_card_count
                 FROM board_column bc LEFT JOIN card c ON c.column_id=bc.id
                 WHERE bc.board_id=CAST(:board AS UUID) AND bc.is_archived=false
                   AND (bc.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
                 GROUP BY bc.id ORDER BY bc.position",
                {board=selected.id,canViewHidden=canManageBoards},{returntype="array"}
            );
        }
        var activeCount=activeBoards.len();
        var maxBoards=access.plan=="premium"?0:3;
        return {
            found=true,
            role=access.role,
            plan=access.plan,
            canManage=canManageBoards,
            canCreateByPolicy=canCreateByPolicy,
            canCreateBoard=canCreateByPolicy && ( maxBoards==0 || activeCount<maxBoards ),
            boardLimitReached=maxBoards>0 && activeCount>=maxBoards,
            maxBoards=maxBoards,
            activeBoards=activeBoards,
            archivedBoards=archivedBoards,
            selectedBoard=selected,
            lanes=lanes
        };
    }

    struct function createBoard(
        required string userId,
        required string workspaceId,
        required string name,
        string description = "",
        string template = "blank"
    ){
        var cleanName=trim(arguments.name);
        if(!cleanName.len() || cleanName.len()>160) return {success=false,code="invalid"};
        var boardId=canonicalUuid(createUUID());
        var outcome={success=false,code="forbidden"};
        transaction {
            var accessRows=queryExecute(
                "SELECT wm.role,w.plan,w.default_locale,w.board_creation_policy
                 FROM workspace w
                 JOIN workspace_member wm
                   ON wm.workspace_id=w.id
                  AND wm.user_id=CAST(:user AS UUID)
                 WHERE w.id=CAST(:workspace AS UUID)
				 FOR UPDATE OF w,wm",
                {user=arguments.userId,workspace=arguments.workspaceId},
                {returntype="array"}
            );
            var access=accessRows.len()?{
                found=true,role=accessRows[1].role,plan=accessRows[1].plan,
                default_locale=accessRows[1].default_locale,
                board_creation_policy=accessRows[1].board_creation_policy
            }:{found=false};
            if(canCreateBoards(access)){
                var activeCount=queryExecute(
                    "SELECT COUNT(*) total FROM board
                     WHERE workspace_id=CAST(:workspace AS UUID) AND is_archived=false",
                    {workspace=arguments.workspaceId},{returntype="array"}
                )[1].total;
                if(access.plan!="premium" && activeCount>=3){
                    outcome={success=false,code="board_limit"};
                } else {
                    var laneNames=templateLanes(arguments.template,access.default_locale);
                    queryExecute(
                        "INSERT INTO board(id,workspace_id,name,description,position)
                         VALUES(CAST(:id AS UUID),CAST(:workspace AS UUID),:name,:description,
                                (SELECT COALESCE(MAX(position),0)+1 FROM board
                                 WHERE workspace_id=CAST(:workspace AS UUID)))",
                        {
                            id=boardId,workspace=arguments.workspaceId,name=cleanName,
                            description=left(trim(arguments.description),2000)
                        }
                    );
                    for(var i=1;i<=laneNames.len();i++){
                        queryExecute(
                            "INSERT INTO board_column(board_id,name,position,color,is_completion_lane)
                             VALUES(CAST(:board AS UUID),:name,CAST(:position AS NUMERIC),:color,
                                    CAST(:isCompletion AS BOOLEAN))",
                            {
                                board=boardId,name=laneNames[i],position=i,color=laneColor(i),
                                isCompletion=i==laneNames.len()
                            }
                        );
                    }
                    outcome={success=true,boardId=boardId};
                }
            }
        }
        return outcome;
    }

    struct function updateBoard(
        required string userId,
        required string workspaceId,
        required string boardId,
        required string name,
        string description = ""
    ){
        var access=boardAccess(arguments.userId,arguments.workspaceId,arguments.boardId);
        if(!canManage(access)) return {success=false,code="forbidden"};
        var cleanName=trim(arguments.name);
        if(!cleanName.len() || cleanName.len()>160) return {success=false,code="invalid"};
        queryExecute(
            "UPDATE board SET name=:name,description=:description,updated_at=now() WHERE id=CAST(:board AS UUID)",
            {name=cleanName,description=left(trim(arguments.description),2000),board=arguments.boardId}
        );
        return {success=true,boardId=arguments.boardId};
    }

    struct function archiveBoard(required string userId,required string workspaceId,required string boardId){
        var access=boardAccess(arguments.userId,arguments.workspaceId,arguments.boardId);
        if(!canManage(access)) return {success=false,code="forbidden"};
        if(access.is_archived) return {success=false,code="not_found"};
        var activeCount=queryExecute(
            "SELECT COUNT(*) total FROM board WHERE workspace_id=CAST(:workspace AS UUID) AND is_archived=false",
            {workspace=arguments.workspaceId},{returntype="array"}
        )[1].total;
        if(activeCount<=1) return {success=false,code="last_board"};
        queryExecute("UPDATE board SET is_archived=true,updated_at=now() WHERE id=CAST(:board AS UUID)",{board=arguments.boardId});
        return {success=true};
    }

    struct function restoreBoard(required string userId,required string workspaceId,required string boardId){
        var access=boardAccess(arguments.userId,arguments.workspaceId,arguments.boardId);
        if(!canManage(access)) return {success=false,code="forbidden"};
        if(!access.is_archived) return {success=false,code="not_found"};
        var activeCount=queryExecute(
            "SELECT COUNT(*) total FROM board WHERE workspace_id=CAST(:workspace AS UUID) AND is_archived=false",
            {workspace=arguments.workspaceId},{returntype="array"}
        )[1].total;
        if(access.plan!="premium" && activeCount>=3) return {success=false,code="board_limit"};
        queryExecute("UPDATE board SET is_archived=false,updated_at=now() WHERE id=CAST(:board AS UUID)",{board=arguments.boardId});
        return {success=true,boardId=arguments.boardId};
    }

    struct function moveBoard(
        required string userId,
        required string workspaceId,
        required string boardId,
        required string direction
    ){
        var access=boardAccess(arguments.userId,arguments.workspaceId,arguments.boardId);
        if(!canManage(access) || access.is_archived) return {success=false,code="forbidden"};
        var boards=queryExecute(
            "SELECT CAST(id AS TEXT) id,position FROM board
             WHERE workspace_id=CAST(:workspace AS UUID) AND is_archived=false
             ORDER BY position,created_at",
            {workspace=arguments.workspaceId},{returntype="array"}
        );
        var currentIndex=0;
        for(var i=1;i<=boards.len();i++) if(boards[i].id==arguments.boardId){currentIndex=i;break;}
        var targetIndex=lCase(arguments.direction)=="left"?currentIndex-1:currentIndex+1;
        if(!currentIndex || targetIndex<1 || targetIndex>boards.len()) return {success=false,code="invalid"};
        transaction {
            queryExecute(
                "UPDATE board SET position=CAST(:position AS NUMERIC),updated_at=now() WHERE id=CAST(:id AS UUID)",
                {position=boards[targetIndex].position,id=boards[currentIndex].id}
            );
            queryExecute(
                "UPDATE board SET position=CAST(:position AS NUMERIC),updated_at=now() WHERE id=CAST(:id AS UUID)",
                {position=boards[currentIndex].position,id=boards[targetIndex].id}
            );
        }
        return {success=true,boardId=arguments.boardId};
    }

    struct function createLane(
        required string userId,
        required string workspaceId,
        required string boardId,
        required string name,
        string color = "red",
        string wipLimit = "",
        boolean hiddenFromMembers = false
    ){
        var validation=validateLane(arguments.name,arguments.color,arguments.wipLimit);
        if(!validation.success) return validation;
        var outcome={success=false,code="forbidden",boardId=arguments.boardId};
        transaction {
            var access=lockBoardForLaneManagement(
                arguments.userId,arguments.workspaceId,arguments.boardId
            );
            if(canManage(access) && !access.is_archived){
                var laneCount=queryExecute(
                    "SELECT COUNT(*) total FROM board_column
                     WHERE board_id=CAST(:board AS UUID) AND is_archived=false",
                    {board=arguments.boardId},{returntype="array"}
                )[1].total;
                if(laneCount>=20){
                    outcome={success=false,code="lane_limit",boardId=arguments.boardId};
                } else {
                    queryExecute(
                        "INSERT INTO board_column(board_id,name,position,wip_limit,color,is_hidden_from_members)
                         VALUES(CAST(:board AS UUID),:name,
                                (SELECT COALESCE(MAX(position),0)+1 FROM board_column
                                 WHERE board_id=CAST(:board AS UUID)),
                                CASE WHEN :wip='' THEN NULL ELSE CAST(:wip AS INTEGER) END,
                                :color,CAST(:hiddenFromMembers AS BOOLEAN))",
                        {
                            board=arguments.boardId,
                            name=validation.name,
                            wip=validation.wip,
                            color=validation.color,
                            hiddenFromMembers=arguments.hiddenFromMembers
                        }
                    );
                    outcome={success=true,boardId=arguments.boardId};
                }
            }
        }
        return outcome;
    }

    struct function updateLane(
        required string userId,
        required string workspaceId,
        required string boardId,
        required string laneId,
        required string name,
        string color = "red",
        string wipLimit = "",
        boolean hiddenFromMembers = false
    ){
        var validation=validateLane(arguments.name,arguments.color,arguments.wipLimit);
        if(!validation.success) return validation;
        var outcome={success=false,code="forbidden",boardId=arguments.boardId};
        transaction {
            var access=lockBoardForLaneManagement(
                arguments.userId,arguments.workspaceId,arguments.boardId
            );
            if(canManage(access) && !access.is_archived){
                var lanes=queryExecute(
                    "SELECT is_completion_lane,is_hidden_from_members
                     FROM board_column
                     WHERE id=CAST(:lane AS UUID)
                       AND board_id=CAST(:board AS UUID)
                       AND is_archived=false
                     FOR UPDATE",
                    {lane=arguments.laneId,board=arguments.boardId},
                    {returntype="array"}
                );
                if(!lanes.len()){
                    outcome={success=false,code="not_found",boardId=arguments.boardId};
                } else if(lanes[1].is_completion_lane && arguments.hiddenFromMembers){
                    outcome={success=false,code="completion_lane_required",boardId=arguments.boardId};
                } else {
                    queryExecute(
                        "UPDATE board_column SET name=:name,
                                wip_limit=CASE WHEN :wip='' THEN NULL ELSE CAST(:wip AS INTEGER) END,
                                color=:color,
                                is_hidden_from_members=CAST(:hiddenFromMembers AS BOOLEAN),
                                updated_at=now()
                         WHERE id=CAST(:lane AS UUID) AND board_id=CAST(:board AS UUID)",
                        {
                            name=validation.name,
                            wip=validation.wip,
                            color=validation.color,
                            hiddenFromMembers=arguments.hiddenFromMembers,
                            lane=arguments.laneId,
                            board=arguments.boardId
                        }
                    );
                    if(!lanes[1].is_completion_lane && !arguments.hiddenFromMembers){
                        queryExecute(
                            "UPDATE card
                             SET completed_at=NULL,
                                 version=version+1,
                                 updated_at=clock_timestamp()
                             WHERE board_id=CAST(:board AS UUID)
                               AND column_id=CAST(:lane AS UUID)
                               AND archived_at IS NULL
                               AND completed_at IS NOT NULL",
                            {board=arguments.boardId,lane=arguments.laneId}
                        );
                    }
                    outcome={success=true,boardId=arguments.boardId};
                }
            }
        }
        return outcome;
    }

    struct function deleteLane(
        required string userId,
        required string workspaceId,
        required string boardId,
        required string laneId
    ){
        var outcome={success=false,code="forbidden",boardId=arguments.boardId};
        transaction {
            var access=lockBoardForLaneManagement(
                arguments.userId,arguments.workspaceId,arguments.boardId
            );
            if(canManage(access) && !access.is_archived){
                var lanes=queryExecute(
                    "SELECT is_completion_lane
                     FROM board_column
                     WHERE id=CAST(:lane AS UUID)
                       AND board_id=CAST(:board AS UUID)
                       AND is_archived=false
                     FOR UPDATE",
                    {lane=arguments.laneId,board=arguments.boardId},
                    {returntype="array"}
                );
                if(!lanes.len()){
                    outcome={success=false,code="not_found",boardId=arguments.boardId};
                } else {
                    var laneCount=queryExecute(
                        "SELECT COUNT(*) total FROM board_column
                         WHERE board_id=CAST(:board AS UUID) AND is_archived=false",
                        {board=arguments.boardId},{returntype="array"}
                    )[1].total;
                    var visibleReplacementCount=queryExecute(
                        "SELECT COUNT(*) total FROM board_column
                         WHERE board_id=CAST(:board AS UUID)
                           AND id<>CAST(:lane AS UUID)
                           AND is_archived=false
                           AND is_hidden_from_members=false",
                        {board=arguments.boardId,lane=arguments.laneId},
                        {returntype="array"}
                    )[1].total;
                    var cardCount=queryExecute(
                        "SELECT COUNT(*) total FROM card
                         WHERE column_id=CAST(:lane AS UUID) AND archived_at IS NULL",
                        {lane=arguments.laneId},{returntype="array"}
                    )[1].total;
                    if(laneCount<=1){
                        outcome={success=false,code="last_lane",boardId=arguments.boardId};
                    } else if(lanes[1].is_completion_lane && !visibleReplacementCount){
                        outcome={success=false,code="completion_lane_required",boardId=arguments.boardId};
                    } else if(cardCount>0){
                        outcome={success=false,code="lane_not_empty",boardId=arguments.boardId};
                    } else {
                        queryExecute(
                            "UPDATE board_column
                             SET is_archived=true,is_completion_lane=false,updated_at=now()
                             WHERE id=CAST(:lane AS UUID)",
                            {lane=arguments.laneId}
                        );
                        if(lanes[1].is_completion_lane){
                            queryExecute(
                                "UPDATE board_column replacement
                                 SET is_completion_lane=true,updated_at=now()
                                 WHERE replacement.id=(
                                     SELECT candidate.id
                                     FROM board_column candidate
                                     WHERE candidate.board_id=CAST(:board AS UUID)
                                       AND candidate.is_archived=false
                                       AND candidate.is_hidden_from_members=false
                                     ORDER BY candidate.position DESC,candidate.created_at DESC,candidate.id DESC
                                     LIMIT 1
                                 )",
                                {board=arguments.boardId}
                            );
                            queryExecute(
                                "UPDATE card card_record
                                 SET completed_at=COALESCE(card_record.completed_at,card_record.updated_at,now()),
                                     started_at=COALESCE(card_record.started_at,card_record.created_at),
                                     version=card_record.version+1,
                                     updated_at=clock_timestamp()
                                 FROM board_column completion_lane
                                 WHERE completion_lane.board_id=CAST(:board AS UUID)
                                   AND completion_lane.is_archived=false
                                   AND completion_lane.is_completion_lane=true
                                   AND card_record.board_id=completion_lane.board_id
                                   AND card_record.column_id=completion_lane.id
                                   AND card_record.archived_at IS NULL
                                   AND card_record.completed_at IS NULL",
                                {board=arguments.boardId}
                            );
                        }
                        outcome={success=true,boardId=arguments.boardId};
                    }
                }
            }
        }
        return outcome;
    }

    struct function moveLane(
        required string userId,
        required string workspaceId,
        required string boardId,
        required string laneId,
        required string direction
    ){
        var outcome={success=false,code="forbidden",boardId=arguments.boardId};
        transaction {
            var access=lockBoardForLaneManagement(
                arguments.userId,arguments.workspaceId,arguments.boardId
            );
            if(canManage(access) && !access.is_archived){
                var lanes=queryExecute(
                    "SELECT CAST(id AS TEXT) id,position FROM board_column
                     WHERE board_id=CAST(:board AS UUID) AND is_archived=false
                     ORDER BY position,created_at,id
                     FOR UPDATE",
                    {board=arguments.boardId},{returntype="array"}
                );
                var currentIndex=0;
                for(var i=1;i<=lanes.len();i++){
                    if(lanes[i].id==arguments.laneId){currentIndex=i;break;}
                }
                var cleanDirection=lCase(trim(arguments.direction));
                var targetIndex=cleanDirection=="up"?currentIndex-1:currentIndex+1;
                if(!listFindNoCase("up,down",cleanDirection) || !currentIndex || targetIndex<1 || targetIndex>lanes.len()){
                    outcome={success=false,code="invalid",boardId=arguments.boardId};
                } else {
                    queryExecute(
                        "UPDATE board_column SET position=-1,updated_at=now()
                         WHERE id=CAST(:id AS UUID)",
                        {id=lanes[currentIndex].id}
                    );
                    queryExecute(
                        "UPDATE board_column SET position=CAST(:position AS NUMERIC),updated_at=now()
                         WHERE id=CAST(:id AS UUID)",
                        {position=lanes[currentIndex].position,id=lanes[targetIndex].id}
                    );
                    queryExecute(
                        "UPDATE board_column SET position=CAST(:position AS NUMERIC),updated_at=now()
                         WHERE id=CAST(:id AS UUID)",
                        {position=lanes[targetIndex].position,id=lanes[currentIndex].id}
                    );
                    outcome={success=true,boardId=arguments.boardId};
                }
            }
        }
        return outcome;
    }

    private struct function lockBoardForLaneManagement(
        required string userId,
        required string workspaceId,
        required string boardId
    ){
        if(!trim(arguments.boardId).len()) return {found=false};
        var rows=queryExecute(
            "SELECT membership.role,workspace_record.plan,board_record.is_archived
             FROM board board_record
             JOIN workspace workspace_record ON workspace_record.id=board_record.workspace_id
             JOIN workspace_member membership
               ON membership.workspace_id=workspace_record.id
              AND membership.user_id=CAST(:user AS UUID)
             WHERE board_record.id=CAST(:board AS UUID)
               AND workspace_record.id=CAST(:workspace AS UUID)
             FOR UPDATE OF board_record
             FOR SHARE OF membership",
            {user=arguments.userId,board=arguments.boardId,workspace=arguments.workspaceId},
            {returntype="array"}
        );
        return rows.len()?{
            found=true,role=rows[1].role,plan=rows[1].plan,is_archived=rows[1].is_archived
        }:{found=false};
    }

    private struct function workspaceAccess(required string userId,required string workspaceId){
        var rows=queryExecute(
            "SELECT wm.role,w.plan,w.default_locale,w.board_creation_policy
             FROM workspace_member wm JOIN workspace w ON w.id=wm.workspace_id
             WHERE wm.user_id=CAST(:user AS UUID) AND wm.workspace_id=CAST(:workspace AS UUID)",
            {user=arguments.userId,workspace=arguments.workspaceId},{returntype="array"}
        );
        return rows.len()?{
            found=true,role=rows[1].role,plan=rows[1].plan,
            default_locale=rows[1].default_locale,
            board_creation_policy=rows[1].board_creation_policy
        }:{found=false};
    }

    private struct function boardAccess(required string userId,required string workspaceId,required string boardId){
        if(!trim(arguments.boardId).len()) return {found=false};
        var rows=queryExecute(
            "SELECT wm.role,w.plan,b.is_archived FROM board b JOIN workspace w ON w.id=b.workspace_id
             JOIN workspace_member wm ON wm.workspace_id=w.id
             WHERE b.id=CAST(:board AS UUID) AND w.id=CAST(:workspace AS UUID) AND wm.user_id=CAST(:user AS UUID)",
            {board=arguments.boardId,workspace=arguments.workspaceId,user=arguments.userId},{returntype="array"}
        );
        return rows.len()?{found=true,role=rows[1].role,plan=rows[1].plan,is_archived=rows[1].is_archived}:{found=false};
    }

    private boolean function canManage(required struct access){
        if(!(arguments.access.found ?: false)) return false;
        return listFindNoCase("owner,admin",arguments.access.role)>0;
    }

    private boolean function canCreateBoards(required struct access){
        if(!(arguments.access.found ?: false)) return false;
        return arguments.access.role=="owner"
            || (
                arguments.access.role=="admin"
                && arguments.access.board_creation_policy=="owner_admin"
            );
    }

    private struct function validateLane(required string name,required string color,required string wipLimit){
        var cleanName=trim(arguments.name);
        var cleanColor=listFindNoCase("red,blue,amber,green,purple,slate",arguments.color)?lCase(arguments.color):"";
        var cleanWip=trim(arguments.wipLimit);
        if(!cleanName.len() || cleanName.len()>120 || !cleanColor.len()) return {success=false,code="invalid"};
        if(cleanWip.len() && (!isValid("integer",cleanWip) || val(cleanWip)<1 || val(cleanWip)>999))
            return {success=false,code="invalid_wip"};
        return {success=true,name=cleanName,color=cleanColor,wip=cleanWip};
    }

    private array function templateLanes(required string template,required string locale){
        var portuguese=arguments.locale=="pt_BR";
        switch(lCase(arguments.template)){
            case "software": return portuguese?["Backlog","Pronto","Em andamento","Revisão","Concluído"]:["Backlog","Ready","In progress","Review","Done"];
            case "marketing": return portuguese?["Ideias","Planejado","Produção","Revisão","Publicado"]:["Ideas","Planned","Creating","Review","Published"];
            case "personal": return portuguese?["A fazer","Fazendo","Concluído"]:["To do","Doing","Done"];
            default: return portuguese?["A fazer","Em andamento","Concluído"]:["To do","In progress","Done"];
        }
    }

    private string function laneColor(required numeric index){
        var colors=["slate","blue","amber","purple","green"];
        return colors[min(arguments.index,colors.len())];
    }

    private string function canonicalUuid(required string value){
        var uuid=lCase(arguments.value);
        return uuid.len()==35 ? left(uuid,23) & "-" & right(uuid,12) : uuid;
    }
}
