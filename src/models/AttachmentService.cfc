component singleton {

    property name="s3StorageService" inject="S3StorageService";

    array function getForCard( required string userId, required string workspaceId, required string cardId ){
        if ( !cardAccess( arguments.userId, arguments.workspaceId, arguments.cardId ).found ) return [];
        return queryExecute(
            "SELECT CAST(a.id AS TEXT) id, a.original_filename, a.content_type, a.size_bytes,
                    a.created_at, COALESCE(u.display_name, '') uploader_name
             FROM attachment a LEFT JOIN app_user u ON u.id=a.uploaded_by
             WHERE a.card_id=CAST(:card AS UUID) AND a.workspace_id=CAST(:workspace AS UUID)
               AND a.status='available' AND a.deleted_at IS NULL
             ORDER BY a.created_at DESC",
            {card=arguments.cardId,workspace=arguments.workspaceId},{returntype="array"}
        );
    }

    struct function initiate(
        required string userId,
        required string workspaceId,
        required string cardId,
        required string filename,
        required string contentType,
        required numeric size
    ){
        var access=cardAccess(arguments.userId,arguments.workspaceId,arguments.cardId);
        if(!access.found) return {success=false,code="forbidden"};
        if(access.role=="viewer") return {success=false,code="read_only"};
        var limits=planLimits(access.plan);
        if(arguments.size<=0 || arguments.size>limits.fileBytes) return {success=false,code="file_too_large"};
        var used=queryExecute(
            "SELECT COALESCE(SUM(size_bytes),0) used FROM attachment WHERE workspace_id=CAST(:workspace AS UUID) AND status='available' AND deleted_at IS NULL",
            {workspace=arguments.workspaceId},{returntype="array"}
        )[1].used;
        if(used+arguments.size>limits.workspaceBytes) return {success=false,code="quota"};
        var safeName=reReplace(listLast(replace(arguments.filename,"\","/","all"),"/"),"[\x00-\x1F]","","all");
        if(!safeName.len()) safeName="attachment";
        safeName=left(safeName,255);
        var extension="";
        if(safeName.find(".")>1) extension="." & lCase(reReplace(listLast(safeName,"."),"[^a-zA-Z0-9]","","all"));
        extension=left(extension,12);
        var attachmentId=lCase(createUUID());
        var objectKey="#arguments.workspaceId#/#arguments.cardId#/#attachmentId##extension#";
        queryExecute(
            "INSERT INTO attachment(id,workspace_id,card_id,object_key,original_filename,content_type,size_bytes,status,uploaded_by)
             VALUES(CAST(:id AS UUID),CAST(:workspace AS UUID),CAST(:card AS UUID),:objectKey,:filename,:contentType,:size,'pending',CAST(:user AS UUID))",
            {id=attachmentId,workspace=arguments.workspaceId,card=arguments.cardId,objectKey=objectKey,
             filename=safeName,contentType=left(arguments.contentType ?: "application/octet-stream",255),
             size={value=arguments.size,sqltype="bigint"},user=arguments.userId}
        );
        return {success=true,id=attachmentId,uploadUrl=s3StorageService.presign("PUT",objectKey,300)};
    }

    struct function complete( required string userId, required string workspaceId, required string cardId, required string attachmentId ){
        var access=cardAccess(arguments.userId,arguments.workspaceId,arguments.cardId);
        if(!access.found || access.role=="viewer") return {success=false,code="forbidden"};
        var rows=queryExecute(
            "SELECT object_key FROM attachment WHERE id=CAST(:id AS UUID) AND workspace_id=CAST(:workspace AS UUID)
             AND card_id=CAST(:card AS UUID) AND status='pending' AND deleted_at IS NULL",
            {id=arguments.attachmentId,workspace=arguments.workspaceId,card=arguments.cardId},{returntype="array"}
        );
        if(!rows.len()) return {success=false,code="not_found"};
        var object=s3StorageService.inspect(rows[1].object_key);
        var limits=planLimits(access.plan);
        if(!object.success || object.size<=0 || object.size>limits.fileBytes){
            queryExecute("UPDATE attachment SET status='rejected' WHERE id=CAST(:id AS UUID)",{id=arguments.attachmentId});
            s3StorageService.delete(rows[1].object_key);
            return {success=false,code=object.size>limits.fileBytes?"file_too_large":"upload_failed"};
        }
        var used=queryExecute(
            "SELECT COALESCE(SUM(size_bytes),0) used FROM attachment
             WHERE workspace_id=CAST(:workspace AS UUID) AND status='available' AND deleted_at IS NULL",
            {workspace=arguments.workspaceId},{returntype="array"}
        )[1].used;
        if(used+object.size>limits.workspaceBytes){
            queryExecute("UPDATE attachment SET status='rejected' WHERE id=CAST(:id AS UUID)",{id=arguments.attachmentId});
            s3StorageService.delete(rows[1].object_key);
            return {success=false,code="quota"};
        }
        queryExecute(
            "UPDATE attachment SET status='available',size_bytes=:size,content_type=:contentType WHERE id=CAST(:id AS UUID)",
            {size={value=object.size,sqltype="bigint"},contentType=left(object.contentType,255),id=arguments.attachmentId}
        );
        recordActivity(arguments.cardId,arguments.userId,"attached");
        return {success=true};
    }

    struct function getDownload( required string userId, required string workspaceId, required string attachmentId ){
        var rows=queryExecute(
            "SELECT a.object_key FROM attachment a JOIN workspace_member wm ON wm.workspace_id=a.workspace_id
             WHERE a.id=CAST(:id AS UUID) AND a.workspace_id=CAST(:workspace AS UUID)
               AND wm.user_id=CAST(:user AS UUID) AND a.status='available' AND a.deleted_at IS NULL",
            {id=arguments.attachmentId,workspace=arguments.workspaceId,user=arguments.userId},{returntype="array"}
        );
        return rows.len()?{success=true,url=s3StorageService.presign("GET",rows[1].object_key,60)}:{success=false};
    }

    struct function remove( required string userId, required string workspaceId, required string cardId, required string attachmentId ){
        var access=cardAccess(arguments.userId,arguments.workspaceId,arguments.cardId);
        if(!access.found || access.role=="viewer") return {success=false,code="forbidden"};
        var rows=queryExecute(
            "SELECT object_key FROM attachment WHERE id=CAST(:id AS UUID) AND workspace_id=CAST(:workspace AS UUID)
             AND card_id=CAST(:card AS UUID) AND deleted_at IS NULL",
            {id=arguments.attachmentId,workspace=arguments.workspaceId,card=arguments.cardId},{returntype="array"}
        );
        if(!rows.len()) return {success=false,code="not_found"};
        if(!s3StorageService.delete(rows[1].object_key)) return {success=false,code="storage"};
        queryExecute("UPDATE attachment SET status='deleted',deleted_at=now() WHERE id=CAST(:id AS UUID)",{id=arguments.attachmentId});
        recordActivity(arguments.cardId,arguments.userId,"detached");
        return {success=true};
    }

    private struct function cardAccess(required string userId,required string workspaceId,required string cardId){
        var rows=queryExecute(
            "SELECT wm.role,w.plan FROM card c JOIN workspace w ON w.id=c.workspace_id
             JOIN workspace_member wm ON wm.workspace_id=c.workspace_id
             WHERE c.id=CAST(:card AS UUID) AND c.workspace_id=CAST(:workspace AS UUID)
               AND wm.user_id=CAST(:user AS UUID) AND c.archived_at IS NULL",
            {card=arguments.cardId,workspace=arguments.workspaceId,user=arguments.userId},{returntype="array"}
        );
        return rows.len()?{found=true,role=rows[1].role,plan=rows[1].plan}:{found=false};
    }

    private struct function planLimits(required string plan){
        return arguments.plan=="premium"
            ? {fileBytes=52428800,workspaceBytes=5368709120}
            : {fileBytes=10485760,workspaceBytes=104857600};
    }

    private void function recordActivity(required string cardId,required string userId,required string action){
        queryExecute("INSERT INTO card_activity(card_id,actor_id,action) VALUES(CAST(:card AS UUID),CAST(:user AS UUID),:action)",
            {card=arguments.cardId,user=arguments.userId,action=arguments.action});
    }
}
