component {

	property name="notificationCenterService" inject="NotificationCenterService";
	property name="authService" inject="AuthService";
	property name="workspaceViewService" inject="WorkspaceViewService";

	this.allowedMethods = {
		index = "GET",
		badge = "GET",
		markRead = "POST",
		markAllRead = "POST"
	};

	function preHandler( event, rc, prc, action, eventArguments ) {
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
		prc.workspaceSwitchCsrfToken = csrfGenerateToken( "workspace-select" );
	}

	function index( event, rc, prc ) {
		prc.page = "notifications";
		prc.pageTitle = $r( "notifications.metaTitle" );
		var requestedFilter = normalizeFilter( rc.filter ?: "all" );
		var requestedPage = normalizePage( rc.page ?: 1 );

		prc.notifications = notificationCenterService.getPage(
			userId=prc.auth.id,
			workspaceId=prc.auth.workspaceId,
			filter=requestedFilter,
			page=requestedPage,
			pageSize=20
		);
		if ( !prc.notifications.found ) relocate( uri="/app" );

		prc.notificationCsrfToken = csrfGenerateToken( "notifications-write" );
		prc.notificationNotice = expectedNotice( rc.notice ?: "" );
		prc.notificationError = expectedError( rc.error ?: "" );
		prc.notificationBadgeOob = false;
		prc.notificationUnreadCount = val( prc.notifications.unreadCount ?: 0 );
		event.setHTTPHeader( name="Cache-Control", value="no-store" );

		if ( isNotificationListRequest() ) {
			prc.isHtmxRequest = true;
			event.setView( view="app/_notificationList", noLayout=true );
			return;
		}

		prc.logoutCsrfToken = csrfGenerateToken( "logout" );
		workspaceViewService.render( event, prc, "app/notifications" );
	}

	function badge( event, rc, prc ) {
		prc.notificationUnreadCount = max(
			0,
			val(
				notificationCenterService.unreadCount(
					userId=prc.auth.id,
					workspaceId=prc.auth.workspaceId
				)
			)
		);
		prc.notificationBadgeOob = false;
		event.setHTTPHeader( name="Cache-Control", value="no-store" );
		event.setView( view="app/_notificationBadge", noLayout=true );
	}

	function markRead( event, rc, prc ) {
		var requestedFilter = normalizeFilter( rc.filter ?: "all" );
		var requestedPage = normalizePage( rc.page ?: 1 );
		var operation = {
			success=false,
			code="invalid"
		};

		if ( !csrfVerifyToken( rc.csrfToken ?: "", "notifications-write" ) ) {
			operation.code = "expired";
		} else if ( isCanonicalUuid( rc.notificationId ?: "" ) ) {
			operation = notificationCenterService.markRead(
				userId=prc.auth.id,
				workspaceId=prc.auth.workspaceId,
				notificationId=rc.notificationId
			);
		}

		if ( operation.success && ( rc.openTarget ?: "" ) == "1" ) {
			var actionTarget = notificationActionTarget( operation.targetUrl ?: "" );
			if ( actionTarget.len() ) relocate( uri=actionTarget );
		}

		if ( isNotificationListRequest() ) {
			renderListAfterWrite(
				event=event,
				prc=prc,
				filter=requestedFilter,
				page=requestedPage,
				notice=operation.success ? "read" : "",
				error=operation.success ? "" : expectedError( operation.code ?: "" )
			);
			return;
		}

		relocate(
			uri=notificationListUrl(
				requestedFilter,
				requestedPage,
				operation.success ? "notice=read" : "error=#urlEncodedFormat( expectedError( operation.code ?: '' ) )#"
			)
		);
	}

	function markAllRead( event, rc, prc ) {
		var requestedFilter = normalizeFilter( rc.filter ?: "all" );
		var operation = {
			success=false,
			code="invalid"
		};

		if ( !csrfVerifyToken( rc.csrfToken ?: "", "notifications-write" ) ) {
			operation.code = "expired";
		} else {
			operation = notificationCenterService.markAllRead(
				userId=prc.auth.id,
				workspaceId=prc.auth.workspaceId
			);
		}

		if ( isNotificationListRequest() ) {
			renderListAfterWrite(
				event=event,
				prc=prc,
				filter=requestedFilter,
				page=1,
				notice=operation.success ? "allRead" : "",
				error=operation.success ? "" : expectedError( operation.code ?: "" )
			);
			return;
		}

		relocate(
			uri=notificationListUrl(
				requestedFilter,
				1,
				operation.success ? "notice=allRead" : "error=#urlEncodedFormat( expectedError( operation.code ?: '' ) )#"
			)
		);
	}

	private void function renderListAfterWrite(
		required any event,
		required struct prc,
		required string filter,
		required numeric page,
		required string notice,
		required string error
	) {
		arguments.prc.notifications = notificationCenterService.getPage(
			userId=arguments.prc.auth.id,
			workspaceId=arguments.prc.auth.workspaceId,
			filter=arguments.filter,
			page=arguments.page,
			pageSize=20
		);
		if ( !arguments.prc.notifications.found ) relocate( uri="/app" );
		arguments.prc.notificationCsrfToken = csrfGenerateToken( "notifications-write" );
		arguments.prc.notificationNotice = expectedNotice( arguments.notice );
		arguments.prc.notificationError = expectedError( arguments.error );
		arguments.prc.notificationBadgeOob = true;
		arguments.prc.notificationUnreadCount = val( arguments.prc.notifications.unreadCount ?: 0 );
		arguments.event.setHTTPHeader( name="Cache-Control", value="no-store" );
		arguments.event.setView( view="app/_notificationList", noLayout=true );
	}

	private string function normalizeFilter( required string value ) {
		var normalized = lCase( trim( arguments.value ) );
		return listFindNoCase( "all,unread", normalized ) ? normalized : "all";
	}

	private numeric function normalizePage( required any value ) {
		var normalized = trim( toString( arguments.value ) );
		return reFind( "^[1-9][0-9]*$", normalized ) ? min( val( normalized ), 100000 ) : 1;
	}

	private boolean function isCanonicalUuid( required string value ) {
		return reFindNoCase(
			"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
			trim( arguments.value )
		) > 0;
	}

	private string function expectedNotice( required string value ) {
		var normalized = lCase( trim( arguments.value ) );
		if ( normalized == "read" ) return "read";
		if ( normalized == "allread" ) return "allRead";
		return "";
	}

	private string function expectedError( required string value ) {
		var normalized = lCase( trim( arguments.value ) );
		return listFindNoCase( "expired,invalid,not_found,forbidden", normalized )
			? normalized
			: ( normalized.len() ? "generic" : "" );
	}

	private string function notificationListUrl(
		required string filter,
		required numeric page,
		required string resultQuery
	) {
		return "/app/notifications?filter=#urlEncodedFormat( arguments.filter )#"
			& "&page=#arguments.page#"
			& ( arguments.resultQuery.len() ? "&#arguments.resultQuery#" : "" );
	}

	private string function notificationActionTarget( required string value ) {
		var target = trim( arguments.value );
		if ( listFindNoCase( "/app,/app/members,/app/profile", target ) ) return target;
		if (
			reFindNoCase(
				"^/app/cards/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
				target
			)
		) return target & "?returnTo=notifications";
		if (
			reFindNoCase(
				"^/app\?boardId=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
				target
			)
		) return target;
		return "";
	}

	private boolean function isNotificationListRequest() {
		var headers = getHttpRequestData().headers ?: {};
		return compareNoCase( headers[ "HX-Request" ] ?: "", "true" ) == 0
			&& compareNoCase( headers[ "HX-Target" ] ?: "", "notification-list" ) == 0
			&& compareNoCase( headers[ "HX-History-Restore-Request" ] ?: "", "true" ) != 0;
	}

}
