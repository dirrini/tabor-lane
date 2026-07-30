component singleton {

    property name="s3StorageService" inject="S3StorageService";

    variables.maxSourceBytes = 5242880;
    variables.maxOutputBytes = 1048576;
    variables.outputPixels = 512;
    variables.allowedSourceTypes = "image/jpeg,image/png,image/webp";

    string function initials( required string displayName ){
        var cleanName = reReplace( trim( arguments.displayName ), "\s+", " ", "all" );
        if ( !cleanName.len() ) return "";
        var nameParts = listToArray( cleanName, " " );
        var result = left( nameParts[ 1 ], 1 );
        if ( nameParts.len() > 1 ) result &= left( nameParts[ nameParts.len() ], 1 );
        return uCase( result );
    }

    struct function getState( required string userId ){
        var rows = queryExecute(
            "SELECT CAST(id AS TEXT) AS id,content_type,size_bytes,width_px,height_px,updated_at
             FROM user_avatar
             WHERE user_id=CAST(:userId AS UUID)
               AND status='available' AND deleted_at IS NULL
             LIMIT 1",
            { userId=arguments.userId },
            { returntype="array" }
        );
        if ( !rows.len() ) return { available=false, id="", url="" };
        return {
            available=true,
            id=rows[ 1 ].id,
            contentType=rows[ 1 ].content_type,
            size=rows[ 1 ].size_bytes,
            width=rows[ 1 ].width_px,
            height=rows[ 1 ].height_px,
            url=avatarUrl( arguments.userId, rows[ 1 ].id )
        };
    }

    struct function initiate(
        required string userId,
        required string filename,
        required string sourceContentType,
        required numeric sourceSize,
        required numeric outputSize
    ){
        var cleanType = lCase( trim( listFirst( arguments.sourceContentType, ";" ) ) );
        if ( !listFindNoCase( variables.allowedSourceTypes, cleanType ) ) {
            return { success=false, code="invalid_type" };
        }
        if ( arguments.sourceSize <= 0 || arguments.sourceSize > variables.maxSourceBytes ) {
            return { success=false, code="source_too_large" };
        }
        if ( arguments.outputSize <= 0 || arguments.outputSize > variables.maxOutputBytes ) {
            return { success=false, code="output_too_large" };
        }

        rejectExpiredPending( arguments.userId );
        var safeName = reReplace(
            listLast( replace( arguments.filename, "\", "/", "all" ), "/" ),
            "[\x00-\x1F]",
            "",
            "all"
        );
        if ( !safeName.len() ) safeName = "avatar";
        safeName = left( safeName, 255 );
        var avatarId = canonicalUuid( createUUID() );
        var objectKey = "avatar-uploads/users/#canonicalUuid( arguments.userId )#/#avatarId#.jpg";
        queryExecute(
            "INSERT INTO user_avatar(
                id,user_id,object_key,original_filename,source_content_type,
                source_size_bytes,content_type,size_bytes,status
             ) VALUES(
                CAST(:id AS UUID),CAST(:userId AS UUID),:objectKey,:filename,:sourceContentType,
                :sourceSize,'image/jpeg',:outputSize,'pending'
             )",
            {
                id=avatarId,
                userId=arguments.userId,
                objectKey=objectKey,
                filename=safeName,
                sourceContentType=cleanType,
                sourceSize={ value=arguments.sourceSize, sqltype="bigint" },
                outputSize={ value=arguments.outputSize, sqltype="bigint" }
            }
        );
        return {
            success=true,
            id=avatarId,
            uploadUrl=s3StorageService.presign( "PUT", objectKey, 300 )
        };
    }

    struct function complete( required string userId, required string avatarId ){
        var result = { success=false, code="not_found" };
        var oldObjects = [];
        var temporaryObjectKey = "";
        var rejectTemporary = false;
        var finalObjectKey = "avatars/users/#canonicalUuid( arguments.userId )#/#arguments.avatarId#.jpg";
        var finalWritten = false;

        try {
            /*
             * Lock the user before inspecting the pending row. Avatar changes
             * for one user are rare, and serializing the complete operation
             * makes repeated/concurrent complete calls safely idempotent.
             */
            transaction {
                var lockedUser = queryExecute(
                    "SELECT CAST(id AS TEXT) AS id
                     FROM app_user
                     WHERE id=CAST(:userId AS UUID)
                     FOR UPDATE",
                    { userId=arguments.userId },
                    { returntype="array" }
                );

                if ( !lockedUser.len() ) {
                    result = { success=false, code="not_found" };
                } else {
                    var avatarRows = queryExecute(
                        "SELECT object_key,status
                         FROM user_avatar
                         WHERE id=CAST(:avatarId AS UUID)
                           AND user_id=CAST(:userId AS UUID)
                           AND deleted_at IS NULL
                         FOR UPDATE",
                        { avatarId=arguments.avatarId, userId=arguments.userId },
                        { returntype="array" }
                    );

                    if ( !avatarRows.len() ) {
                        result = { success=false, code="not_found" };
                    } else if ( avatarRows[ 1 ].status == "available" ) {
                        result = {
                            success=true,
                            id=arguments.avatarId,
                            url=avatarUrl( arguments.userId, arguments.avatarId )
                        };
                    } else if ( avatarRows[ 1 ].status != "pending" ) {
                        result = { success=false, code="not_found" };
                    } else {
                        temporaryObjectKey = avatarRows[ 1 ].object_key;
                        var objectInfo = s3StorageService.inspect( temporaryObjectKey );

                        if (
                            !objectInfo.success
                            || objectInfo.size <= 0
                            || objectInfo.size > variables.maxOutputBytes
                            || compareNoCase( listFirst( objectInfo.contentType, ";" ), "image/jpeg" ) != 0
                        ) {
                            rejectTemporary = true;
                            result = {
                                success=false,
                                code=objectInfo.size > variables.maxOutputBytes
                                    ? "output_too_large"
                                    : "invalid_output"
                            };
                        } else {
                            var objectData = s3StorageService.readObject(
                                temporaryObjectKey,
                                variables.maxOutputBytes
                            );
                            if ( !objectData.success ) {
                                rejectTemporary = true;
                                result = {
                                    success=false,
                                    code=( objectData.tooLarge ?: false )
                                        ? "output_too_large"
                                        : "invalid_output"
                                };
                            } else {
                                var normalizedImage = normalizeJpeg( objectData.data );
                                if ( !normalizedImage.valid ) {
                                    rejectTemporary = true;
                                    result = {
                                        success=false,
                                        code=normalizedImage.code ?: "invalid_output"
                                    };
                                } else {
                                    var finalWrite = s3StorageService.writeObject(
                                        objectKey=finalObjectKey,
                                        data=normalizedImage.data,
                                        contentType="image/jpeg"
                                    );
                                    if ( !finalWrite.success ) {
                                        s3StorageService.delete( finalObjectKey );
                                        result = { success=false, code="invalid_output" };
                                    } else {
                                        finalWritten = true;
                                        var previous = queryExecute(
                                            "SELECT object_key
                                             FROM user_avatar
                                             WHERE user_id=CAST(:userId AS UUID)
                                               AND status='available' AND deleted_at IS NULL
                                             FOR UPDATE",
                                            { userId=arguments.userId },
                                            { returntype="array" }
                                        );
                                        for ( var oldAvatar in previous ) {
                                            oldObjects.append( oldAvatar.object_key );
                                        }
                                        queryExecute(
                                            "UPDATE user_avatar
                                             SET status='deleted',deleted_at=now(),updated_at=now()
                                             WHERE user_id=CAST(:userId AS UUID)
                                               AND status='available' AND deleted_at IS NULL",
                                            { userId=arguments.userId }
                                        );
                                        var madeAvailable = queryExecute(
                                            "UPDATE user_avatar
                                             SET object_key=:finalObjectKey,status='available',
                                                 content_type='image/jpeg',size_bytes=:size,
                                                 width_px=:width,height_px=:height,updated_at=now()
                                             WHERE id=CAST(:avatarId AS UUID)
                                               AND user_id=CAST(:userId AS UUID)
                                               AND status='pending' AND deleted_at IS NULL
                                             RETURNING CAST(id AS TEXT) AS id",
                                            {
                                                finalObjectKey=finalObjectKey,
                                                size={
                                                    value=normalizedImage.size,
                                                    sqltype="bigint"
                                                },
                                                width={
                                                    value=variables.outputPixels,
                                                    sqltype="integer"
                                                },
                                                height={
                                                    value=variables.outputPixels,
                                                    sqltype="integer"
                                                },
                                                avatarId=arguments.avatarId,
                                                userId=arguments.userId
                                            },
                                            { returntype="array" }
                                        );
                                        if ( !madeAvailable.len() ) {
                                            throw(
                                                type="AvatarCompletionConflict",
                                                message="Pending avatar changed while completing"
                                            );
                                        }
                                        result = {
                                            success=true,
                                            id=arguments.avatarId,
                                            url=avatarUrl( arguments.userId, arguments.avatarId )
                                        };
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch ( any exception ) {
            if ( finalWritten ) s3StorageService.delete( finalObjectKey );
            rethrow;
        }

        if ( result.success ) {
            if ( temporaryObjectKey.len() ) s3StorageService.delete( temporaryObjectKey );
            for ( var oldObjectKey in oldObjects ) s3StorageService.delete( oldObjectKey );
        } else if ( rejectTemporary && temporaryObjectKey.len() ) {
            rejectUpload( arguments.avatarId, temporaryObjectKey );
        }
        return result;
    }

    struct function remove( required string userId ){
        var oldObjects = [];
        transaction {
            queryExecute(
                "SELECT id FROM app_user WHERE id=CAST(:userId AS UUID) FOR UPDATE",
                { userId=arguments.userId }
            );
            var previous = queryExecute(
                "SELECT object_key
                 FROM user_avatar
                 WHERE user_id=CAST(:userId AS UUID)
                   AND status='available' AND deleted_at IS NULL
                 FOR UPDATE",
                { userId=arguments.userId },
                { returntype="array" }
            );
            for ( var oldAvatar in previous ) oldObjects.append( oldAvatar.object_key );
            queryExecute(
                "UPDATE user_avatar
                 SET status='deleted',deleted_at=now(),updated_at=now()
                 WHERE user_id=CAST(:userId AS UUID)
                   AND status='available' AND deleted_at IS NULL",
                { userId=arguments.userId }
            );
        }
        for ( var objectKey in oldObjects ) s3StorageService.delete( objectKey );
        return { success=true };
    }

    struct function getDownload(
        required string requesterId,
        required string workspaceId,
        required string targetUserId
    ){
        var rows = queryExecute(
            "SELECT avatar.object_key
             FROM app_user target
             JOIN workspace_member target_membership
               ON target_membership.user_id=target.id
              AND target_membership.workspace_id=CAST(:workspaceId AS UUID)
             JOIN workspace_member requester_membership
               ON requester_membership.workspace_id=target_membership.workspace_id
              AND requester_membership.user_id=CAST(:requesterId AS UUID)
             JOIN user_avatar avatar
               ON avatar.user_id=target.id
              AND avatar.status='available' AND avatar.deleted_at IS NULL
             WHERE target.id=CAST(:targetUserId AS UUID)
             LIMIT 1",
            {
                requesterId=arguments.requesterId,
                workspaceId=arguments.workspaceId,
                targetUserId=arguments.targetUserId
            },
            { returntype="array" }
        );
        return rows.len()
            ? { success=true, url=s3StorageService.presign( "GET", rows[ 1 ].object_key, 60 ) }
            : { success=false };
    }

    private string function avatarUrl( required string userId, required string avatarId ){
        return "/app/users/#canonicalUuid( arguments.userId )#/avatar?v=#canonicalUuid( arguments.avatarId )#";
    }

    private string function canonicalUuid( required string value ){
        var compact = lCase( replace( arguments.value, "-", "", "all" ) );
        if ( !reFind( "^[0-9a-f]{32}$", compact ) ) {
            throw( type="Avatar.InvalidUuid", message="Could not generate a valid avatar UUID." );
        }
        return left( compact, 8 )
            & "-" & mid( compact, 9, 4 )
            & "-" & mid( compact, 13, 4 )
            & "-" & mid( compact, 17, 4 )
            & "-" & right( compact, 12 );
    }

    private void function rejectExpiredPending( required string userId ){
        var expired = queryExecute(
            "SELECT CAST(id AS TEXT) AS id,object_key
             FROM user_avatar
             WHERE user_id=CAST(:userId AS UUID)
               AND status='pending' AND created_at<now()-INTERVAL '15 minutes'",
            { userId=arguments.userId },
            { returntype="array" }
        );
        for ( var upload in expired ) rejectUpload( upload.id, upload.object_key );
    }

    private boolean function rejectUpload( required string avatarId, required string objectKey ){
        var rejected = queryExecute(
            "UPDATE user_avatar
             SET status='rejected',deleted_at=now(),updated_at=now()
             WHERE id=CAST(:avatarId AS UUID)
               AND object_key=:objectKey
               AND status='pending' AND deleted_at IS NULL
             RETURNING object_key",
            { avatarId=arguments.avatarId, objectKey=arguments.objectKey },
            { returntype="array" }
        );
        if ( !rejected.len() ) return false;
        s3StorageService.delete( rejected[ 1 ].object_key );
        return true;
    }

    private struct function normalizeJpeg( required binary imageData ){
        var result = {
            valid=false,
            code="invalid_output",
            width=0,
            height=0,
            size=0
        };
        var byteStream = "";
        var imageStream = "";
        var imageReader = "";
        var outputStream = "";
        var hasReader = false;
        try {
            byteStream = createObject( "java", "java.io.ByteArrayInputStream" ).init( arguments.imageData );
            imageStream = createObject( "java", "javax.imageio.ImageIO" ).createImageInputStream( byteStream );
            if ( isNull( imageStream ) ) return result;
            var readers = createObject( "java", "javax.imageio.ImageIO" ).getImageReaders( imageStream );
            if ( !readers.hasNext() ) return result;
            imageReader = readers.next();
            hasReader = true;
            imageReader.setInput( imageStream, true, true );
            var formatName = uCase( imageReader.getFormatName() );
            result.width = imageReader.getWidth( 0 );
            result.height = imageReader.getHeight( 0 );
            if ( formatName != "JPEG" ) return result;
            if (
                result.width != variables.outputPixels
                || result.height != variables.outputPixels
            ) {
                result.code = "invalid_dimensions";
                return result;
            }

            // Fully decode the raster before accepting it. Writing a fresh
            // JPEG strips metadata and any bytes appended to the source file.
            var decodedImage = imageReader.read( 0 );
            if ( isNull( decodedImage ) ) return result;
            outputStream = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
            var encoded = createObject( "java", "javax.imageio.ImageIO" ).write(
                decodedImage,
                "JPEG",
                outputStream
            );
            if ( !encoded ) return result;
            var normalizedData = outputStream.toByteArray();
            var normalizedSize = createObject(
                "java",
                "java.lang.reflect.Array"
            ).getLength( normalizedData );
            if ( normalizedSize <= 0 || normalizedSize > variables.maxOutputBytes ) {
                result.code = "output_too_large";
                return result;
            }
            result.valid = true;
            result.code = "";
            result.size = normalizedSize;
            result.data = normalizedData;
        } catch ( any exception ) {
            result = {
                valid=false,
                code="invalid_output",
                width=0,
                height=0,
                size=0
            };
        } finally {
            if ( hasReader ) imageReader.dispose();
            if ( isObject( outputStream ) ) outputStream.close();
            if ( isObject( imageStream ) ) imageStream.close();
            if ( isObject( byteStream ) ) byteStream.close();
        }
        return result;
    }

}
