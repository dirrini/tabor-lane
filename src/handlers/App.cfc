component {

    variables.activeBoardStreams = { total=0,users={} };

    property name="boardService" inject="BoardService";
    property name="workspaceService" inject="WorkspaceService";
    property name="notificationService" inject="NotificationService";
    property name="rateLimitService" inject="RateLimitService";
    property name="authService" inject="AuthService";
    property name="workspaceViewService" inject="WorkspaceViewService";
    property name="attachmentService" inject="AttachmentService";

    this.allowedMethods = {
        index = "GET",
        boardEvents = "GET",
        boardRevision = "GET",
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
        // SSE clients need an HTTP response instead of an HTML redirect. The
        // boardEvents action performs the authoritative membership/board/plan
        // lookup before opening the stream.
        if ( arguments.action == "boardEvents" ) {
            prc.boardEventsAuthCode = "";
            if ( !structKeyExists( session, "auth" ) ) {
                prc.boardEventsAuthCode = "unauthorized";
                return;
            }
            if (
                !isCanonicalUuid( session.auth.id ?: "" )
                || !isCanonicalUuid( session.auth.workspaceId ?: "" )
            ) {
                prc.boardEventsAuthCode = "unauthorized";
                return;
            }
            if ( !authService.isEmailVerified( session.auth.id ) ) {
                prc.boardEventsAuthCode = "email_unverified";
                return;
            }
            prc.auth = session.auth;
            return;
        }
        if ( !structKeyExists( session, "auth" ) ) {
            relocate( uri = "/login" );
        }
        // Revision polling is read-only and revalidates workspace membership in
        // BoardService. Avoid the full workspace/session refresh on every tick.
        if ( arguments.action == "boardRevision" ) {
            if ( !( session.auth.emailVerified ?: false ) ) {
                relocate( uri = "/check-email" );
            }
            prc.auth = session.auth;
            return;
        }
        session.auth.emailVerified = authService.isEmailVerified( session.auth.id );
        if ( !session.auth.emailVerified ) {
            relocate( uri = "/check-email" );
        }
        var workspaceContext = authService.resolveWorkspaceContext(
            session.auth.id,
            session.auth.workspaceId ?: ""
        );
        if ( !workspaceContext.found ) {
            sessionInvalidate();
            relocate( uri = "/login" );
        }
        session.auth.workspaceId = workspaceContext.workspaceId;
        session.auth.workspaceName = workspaceContext.workspaceName;
        session.auth.role = workspaceContext.role;
        prc.auth = session.auth;
        prc.workspaceSwitchCsrfToken = csrfGenerateToken( "workspace-select" );
    }

    function members( event, rc, prc ) {
        prc.page = "members";
        prc.pageTitle = $r( "members.title" );
        prc.members = workspaceService.getMembers( prc.auth.id, prc.auth.workspaceId );
        prc.invitations = workspaceService.getPendingInvitations( prc.auth.id, prc.auth.workspaceId );
        prc.canInvite = workspaceService.canInviteMembers( prc.auth.id, prc.auth.workspaceId );
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
            role = rc.role ?: "member"
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
        prc.boardError = listFindNoCase( "wip_limit,invalid", rc.error ?: "" )
            ? lCase( rc.error )
            : "";
        workspaceViewService.render( event, prc, "app/index" );
    }

    function boardRevision( event, rc, prc ) {
        var result = boardService.getBoardRevision(
            prc.auth.id,
            prc.auth.workspaceId,
            rc.boardId ?: ""
        );
        event.setHTTPHeader( name="Cache-Control", value="private, no-cache, must-revalidate" );
        event.setHTTPHeader( name="Vary", value="Cookie" );
        if ( !result.found ) {
            event.renderData( type="json", data={ found=false }, statusCode=404 );
            return;
        }

        var etag = '"board-' & lCase( rc.boardId ) & '-' & result.revision & '"';
        event.setHTTPHeader( name="ETag", value=etag );
        if ( trim( cgi.http_if_none_match ?: "" ) == etag ) {
            event.renderData( type="json", data={}, statusCode=304 );
            return;
        }
        event.renderData(
            type="json",
            data={ found=true,revision=result.revision },
            statusCode=200
        );
    }

    function boardEvents( event, rc, prc ) {
        event.setHTTPHeader( name="Cache-Control", value="no-cache, no-store, no-transform" );
        event.setHTTPHeader( name="Pragma", value="no-cache" );
        event.setHTTPHeader( name="Vary", value="Cookie" );
        event.setHTTPHeader( name="X-Content-Type-Options", value="nosniff" );

        var authCode = prc.boardEventsAuthCode ?: "unauthorized";
        if ( authCode.len() ) {
            event.renderData(
                type="json",
                data={ success=false,code=authCode },
                statusCode=authCode == "email_unverified" ? 403 : 401
            );
            return;
        }

        var boardId = lCase( trim( rc.boardId ?: "" ) );
        var userId = prc.auth.id;
        var workspaceId = prc.auth.workspaceId;
        if ( !isCanonicalUuid( boardId ) ) {
            event.renderData(
                type="json",
                data={ success=false,code="not_found" },
                statusCode=404
            );
            return;
        }

        // Apply the connection-start limit before any database lookup. This
        // bounds malformed, Free-plan and reconnect-storm requests equally,
        // without allowing them to repeatedly execute the revision aggregates.
        // A 22-second stream naturally reconnects fewer than three times per
        // minute. Twenty starts/minute leaves room for roughly five or six
        // tabs and manual refreshes while still containing abuse per user.
        if (
            !rateLimitService.allow(
                "board-events:#userId#",
                20,
                60,
                compareNoCase( server.system.environment.APP_ENV ?: "development", "production" ) == 0
            )
        ) {
            event.setHTTPHeader( name="Retry-After", value="10" );
            event.renderData(
                type="json",
                data={ success=false,code="rate_limit_exceeded" },
                statusCode=429
            );
            return;
        }

        // This single lookup revalidates the explicit workspace membership,
        // board ownership and current plan before any SSE headers are emitted.
        var access = boardService.getBoardRevision(
            userId,
            workspaceId,
            boardId
        );
        if ( !access.found ) {
            event.renderData(
                type="json",
                data={ success=false,code="not_found" },
                statusCode=404
            );
            return;
        }
        if ( compareNoCase( access.plan ?: "free", "premium" ) != 0 ) {
            event.renderData(
                type="json",
                data={ success=false,code="plan_required" },
                statusCode=403
            );
            return;
        }

        // SSE holds one servlet request while connected. Keep enough request
        // capacity available for normal application traffic on the first
        // single-VM deployment. The browser falls back to revision polling
        // while all realtime slots are occupied.
        if ( !acquireBoardStream( userId ) ) {
            event.setHTTPHeader( name="Retry-After", value="5" );
            event.renderData(
                type="json",
                data={ success=false,code="realtime_capacity" },
                statusCode=503
            );
            return;
        }

        try {
            event.noRender();
            event.setHTTPHeader( name="Content-Type", value="text/event-stream; charset=utf-8" );
            event.setHTTPHeader( name="X-Accel-Buffering", value="no" );

            var lineFeed = chr( 10 );
            var startedAt = getTickCount();
            var lastWriteAt = startedAt;
            var currentRevision = access.revision;
            var streamDurationMs = 22000;
            var pollIntervalMs = 2000;
            var heartbeatIntervalMs = 8000;

            writeOutput( "retry: 3000#lineFeed##lineFeed#" );
            writeBoardEvent( "connected", currentRevision, lineFeed );
            flushBoardEvents();

            while ( getTickCount() - startedAt < streamDurationMs ) {
                sleep( pollIntervalMs );

                // Rechecking through the same access query means removing the
                // member, archiving the board or downgrading the workspace
                // closes the stream on the next polling cycle.
                var refreshed = boardService.getBoardRevision(
                    userId,
                    workspaceId,
                    boardId
                );
                if ( !refreshed.found ) return;

                var nowTick = getTickCount();
                if ( refreshed.revision != currentRevision ) {
                    currentRevision = refreshed.revision;
                    writeBoardEvent( "board.updated", currentRevision, lineFeed );
                    flushBoardEvents();
                    // The browser closes this source and reloads the board on
                    // board.updated. Return immediately instead of occupying
                    // the request thread until the normal stream timeout.
                    return;
                }

                // Send the changed revision before closing a workspace that
                // was downgraded. The client can then reload once and render
                // the Free experience without reopening an SSE connection.
                if ( compareNoCase( refreshed.plan ?: "free", "premium" ) != 0 ) {
                    return;
                }

                if ( nowTick - lastWriteAt >= heartbeatIntervalMs ) {
                    writeBoardEvent( "heartbeat", currentRevision, lineFeed );
                    flushBoardEvents();
                    lastWriteAt = nowTick;
                }
            }

            writeBoardEvent( "reconnect", currentRevision, lineFeed );
            flushBoardEvents();
        } catch ( any streamException ) {
            // Client disconnects are normal for short-lived SSE connections.
            // Unexpected SQL/programming failures are logged, but nothing is
            // written to a servlet response that may already be committed.
            if ( !isBoardStreamDisconnect( streamException ) ) {
                var safeMessage = left(
                    replace(
                        replace( streamException.message ?: "Unknown SSE error", chr( 13 ), " ", "all" ),
                        chr( 10 ),
                        " ",
                        "all"
                    ),
                    500
                );
                writeLog(
                    file="application",
                    type="error",
                    text="Board SSE failed for user #userId#, board #boardId#: #safeMessage#"
                );
            }
            return;
        } finally {
            releaseBoardStream( userId );
        }
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
            if ( ( result.boardId ?: "" ).len() ) {
                relocate(
                    uri="/app?boardId=#urlEncodedFormat(result.boardId)#&error=#urlEncodedFormat(result.code ?: 'invalid')#"
                );
            }
        }
        relocate( uri = "/app" );
    }

    function cardDetails( event, rc, prc ) {
        prc.returnTo = normalizeCardReturnTo( rc.returnTo ?: "" );
        prc.analyticsReturnFilters = normalizeAnalyticsReturnFilters( rc );
        prc.analyticsReturnUrl = buildAnalyticsReturnUrl( prc.analyticsReturnFilters );
        prc.page = prc.returnTo == "my-work"
            ? "myWork"
            : prc.returnTo == "analytics"
                ? "analytics"
                : prc.returnTo == "notifications" ? "notifications" : "app";
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
        var returnTo = normalizeCardReturnTo( rc.returnTo ?: "" );
        var returnQuery = buildCardReturnQuery( returnTo, rc );
        if (
            !csrfVerifyToken( rc.csrfToken ?: "", "card-write" )
            || !trim( rc.title ?: "" ).len()
            || trim( rc.title ?: "" ).len() > 255
            || ( trim( rc.dueDate ?: "" ).len() && !isValid( "date", rc.dueDate ) )
        ) {
            relocate( uri="/app/cards/#rc.cardId#?error=invalid#returnQuery#" );
        }
        var result = boardService.updateCard( prc.auth.id, prc.auth.workspaceId, rc.cardId, rc );
        var redirectQuery = result.success
            ? "updated=1"
            : "error=" & urlEncodedFormat( result.code ?: "generic" );
        redirectQuery &= returnQuery;
        relocate( uri="/app/cards/#rc.cardId#?#redirectQuery#" );
    }

    function addCardComment( event, rc, prc ) {
        var returnTo = normalizeCardReturnTo( rc.returnTo ?: "" );
        var returnQuery = buildCardReturnQuery( returnTo, rc );
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "card-write" ) ) {
            relocate( uri="/app/cards/#rc.cardId#?error=expired#returnQuery#" );
        }
        var result = boardService.addComment( prc.auth.id, prc.auth.workspaceId, rc.cardId, rc.body ?: "" );
        var redirectQuery = result.success
            ? "commented=1"
            : "error=" & urlEncodedFormat( result.code ?: "generic" );
        redirectQuery &= returnQuery;
        relocate( uri="/app/cards/#rc.cardId#?#redirectQuery#" );
    }

    function archiveCard( event, rc, prc ) {
        var returnTo = normalizeCardReturnTo( rc.returnTo ?: "" );
        var returnQuery = buildCardReturnQuery( returnTo, rc );
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "card-write" ) ) {
            relocate( uri="/app/cards/#rc.cardId#?error=expired#returnQuery#" );
        }
        var result = boardService.archiveCard( prc.auth.id, prc.auth.workspaceId, rc.cardId );
        if ( result.success && returnTo == "my-work" ) relocate( uri="/app/my-work" );
        if ( result.success && returnTo == "analytics" ) {
            relocate( uri=buildAnalyticsReturnUrl( normalizeAnalyticsReturnFilters( rc ) ) );
        }
        if ( result.success && returnTo == "notifications" ) {
            relocate( uri="/app/notifications" );
        }
        var boardQuery=result.boardId ?: "";
        var failureUri = "/app/cards/" & rc.cardId
            & "?error=" & urlEncodedFormat( result.code ?: "generic" )
            & returnQuery;
        relocate( uri=result.success ? "/app?boardId=#urlEncodedFormat(boardQuery)#&cardArchived=1" : failureUri );
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
        if ( structKeyExists( result, "revision" ) ) {
            responseData[ "revision" ] = result.revision;
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

    private string function normalizeCardReturnTo( required string value ) {
        var normalized = lCase( trim( arguments.value ) );
        return listFindNoCase( "my-work,analytics,notifications", normalized ) ? normalized : "board";
    }

    private struct function normalizeAnalyticsReturnFilters( required struct source ) {
        var normalized = {
            fromDate = "",
            toDate = "",
            boardId = "",
            assigneeId = ""
        };
        var requestedFrom = trim( arguments.source.returnFromDate ?: "" );
        var requestedTo = trim( arguments.source.returnToDate ?: "" );
        var requestedBoard = lCase( trim( arguments.source.returnBoardId ?: "" ) );
        var requestedAssignee = lCase( trim( arguments.source.returnAssigneeId ?: "" ) );

        if ( isIsoDate( requestedFrom ) ) normalized.fromDate = requestedFrom;
        if ( isIsoDate( requestedTo ) ) normalized.toDate = requestedTo;
        if ( isCanonicalUuid( requestedBoard ) ) normalized.boardId = requestedBoard;
        if ( isCanonicalUuid( requestedAssignee ) ) normalized.assigneeId = requestedAssignee;
        return normalized;
    }

    private string function buildCardReturnQuery(
        required string returnTo,
        required struct source
    ) {
        if ( arguments.returnTo == "board" ) return "";
        var query = "&returnTo=" & arguments.returnTo;
        if ( arguments.returnTo != "analytics" ) return query;

        var filters = normalizeAnalyticsReturnFilters( arguments.source );
        if ( filters.fromDate.len() ) query &= "&returnFromDate=" & urlEncodedFormat( filters.fromDate );
        if ( filters.toDate.len() ) query &= "&returnToDate=" & urlEncodedFormat( filters.toDate );
        if ( filters.boardId.len() ) query &= "&returnBoardId=" & urlEncodedFormat( filters.boardId );
        if ( filters.assigneeId.len() ) query &= "&returnAssigneeId=" & urlEncodedFormat( filters.assigneeId );
        return query;
    }

    private string function buildAnalyticsReturnUrl( required struct filters ) {
        var pairs = [];
        if ( arguments.filters.fromDate.len() ) pairs.append( "fromDate=" & urlEncodedFormat( arguments.filters.fromDate ) );
        if ( arguments.filters.toDate.len() ) pairs.append( "toDate=" & urlEncodedFormat( arguments.filters.toDate ) );
        if ( arguments.filters.boardId.len() ) pairs.append( "boardId=" & urlEncodedFormat( arguments.filters.boardId ) );
        if ( arguments.filters.assigneeId.len() ) pairs.append( "assigneeId=" & urlEncodedFormat( arguments.filters.assigneeId ) );
        return "/app/analytics" & ( pairs.len() ? "?" & arrayToList( pairs, "&" ) : "" );
    }

    private boolean function isIsoDate( required string value ) {
        return reFind( "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", arguments.value )
            && isValid( "date", arguments.value );
    }

    private boolean function isCanonicalUuid( required string value ) {
        return reFindNoCase(
            "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            arguments.value
        ) > 0;
    }

    private boolean function acquireBoardStream( required string userId ) {
        var acquired = false;
        var streamUserKey = lCase( arguments.userId );
        lock name="tabor-lane-board-stream-capacity" type="exclusive" timeout="2" {
            var userCount = variables.activeBoardStreams.users[ streamUserKey ] ?: 0;
            if ( variables.activeBoardStreams.total < 20 && userCount < 4 ) {
                variables.activeBoardStreams.total++;
                variables.activeBoardStreams.users[ streamUserKey ] = userCount + 1;
                acquired = true;
            }
        }
        return acquired;
    }

    private void function releaseBoardStream( required string userId ) {
        var streamUserKey = lCase( arguments.userId );
        lock name="tabor-lane-board-stream-capacity" type="exclusive" timeout="2" {
            var userCount = variables.activeBoardStreams.users[ streamUserKey ] ?: 0;
            if ( userCount > 0 ) {
                variables.activeBoardStreams.total = max( 0, variables.activeBoardStreams.total - 1 );
                if ( userCount == 1 ) {
                    structDelete( variables.activeBoardStreams.users, streamUserKey );
                } else {
                    variables.activeBoardStreams.users[ streamUserKey ] = userCount - 1;
                }
            }
        }
    }

    private boolean function isBoardStreamDisconnect( required any exception ) {
        var description = lCase(
            ( arguments.exception.type ?: "" ) & " "
            & ( arguments.exception.message ?: "" ) & " "
            & ( arguments.exception.detail ?: "" )
        );
        return reFind(
            "clientabort|broken pipe|connection reset|stream[^a-z]+closed|response[^a-z]+closed|ut010029",
            description
        ) > 0;
    }

    private void function writeBoardEvent(
        required string eventName,
        required string revision,
        required string lineFeed
    ) {
        var payload = {};
        payload[ "revision" ] = arguments.revision;
        writeOutput(
            "event: #arguments.eventName##arguments.lineFeed#"
            & "data: #serializeJSON( payload )##arguments.lineFeed##arguments.lineFeed#"
        );
    }

    private void function flushBoardEvents() {
        getPageContext().getOut().flush();
        getPageContext().getResponse().flushBuffer();
    }

}
