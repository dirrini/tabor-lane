<cfscript>
	notificationPage = prc.notifications ?: {
		found=true,
		code="ok",
		items=[],
		page=1,
		pageSize=20,
		total=0,
		totalPages=0,
		filter="all",
		unreadCount=0
	};
	notificationItems = notificationPage.items ?: ( notificationPage.notifications ?: [] );
	notificationFilter = listFindNoCase( "all,unread", notificationPage.filter ?: "" )
		? lCase( notificationPage.filter )
		: "all";
	notificationCurrentPage = max( 1, val( notificationPage.page ?: 1 ) );
	notificationTotalPages = max( 0, val( notificationPage.totalPages ?: 0 ) );
	notificationTotal = max( 0, val( notificationPage.total ?: 0 ) );
	notificationUnreadCount = max( 0, val( notificationPage.unreadCount ?: 0 ) );
	notificationNotice = lCase( prc.notificationNotice ?: "" );
	notificationError = lCase( prc.notificationError ?: "" );
	notificationLocale = getFWLocale();
	notificationDateMask = notificationLocale == "pt_BR"
		? "dd/MM/yyyy 'às' HH:mm"
		: "MMM d, yyyy 'at' h:mm tt";

	notificationDateLabel = function( required string value ){
		if ( !isValid( "date", arguments.value ) ) return arguments.value;
		return dateTimeFormat( parseDateTime( arguments.value ), notificationDateMask );
	};

	notificationEventType = function( required struct item ){
		var normalized = lCase(
			trim(
				arguments.item.eventType
					?: arguments.item.type
					?: arguments.item.event_type
					?: arguments.item.notification_type
					?: "generic"
			)
		);
		normalized = replace( normalized, ".", "_", "all" );
		var aliases = {
			assignment="card_assigned",
			assigned="card_assigned",
			comment="card_commented",
			mention="card_mentioned",
			due_soon="card_due_soon",
			moved="card_moved",
			updated="card_updated"
		};
		return structKeyExists( aliases, normalized ) ? aliases[ normalized ] : normalized;
	};

	notificationEventIcon = function( required string eventType ){
		var icons = {
			card_assigned="users",
			card_commented="mail",
			card_mentioned="alert",
			card_due_soon="clock",
			card_moved="arrow-right",
			card_reordered="columns",
			card_updated="board",
			card_created="plus",
			card_archived="archive",
			workspace_member_joined="users"
		};
		return structKeyExists( icons, arguments.eventType ) ? icons[ arguments.eventType ] : "bell";
	};

	notificationEventMessage = function( required struct item, required string eventType ){
		var supportedEvents = "card_assigned,card_commented,card_mentioned,card_due_soon,card_moved,card_reordered,card_updated,card_created,card_archived,workspace_member_joined";
		var messageKey = listFindNoCase( supportedEvents, arguments.eventType )
			? "notifications.event.#arguments.eventType#"
			: "notifications.event.generic";
		var actorName = trim( arguments.item.actorName ?: "" );
		var cardTitle = trim( arguments.item.cardTitle ?: "" );
		var message = $r( messageKey );
		message = replace(
			message,
			"{actor}",
			actorName.len() ? actorName : $r( "notifications.system" ),
			"all"
		);
		message = replace(
			message,
			"{card}",
			cardTitle.len() ? cardTitle : $r( "notifications.cardFallback" ),
			"all"
		);
		return message;
	};

	notificationActionUrl = function( required struct item ){
		var target = trim( arguments.item.targetUrl ?: "" );
		if ( listFindNoCase( "/app,/app/members,/app/profile", target ) ) return target;
		if (
			reFindNoCase(
				"^/app/cards/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
				target
			)
			|| reFindNoCase(
				"^/app\?boardId=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
				target
			)
		) return target;
		return "";
	};

	notificationNavigationUrl = function( required string target ){
		return arguments.target.findNoCase( "/app/cards/" ) == 1
			? arguments.target & "?returnTo=notifications"
			: arguments.target;
	};

	notificationActionLabel = function( required string target ){
		if ( arguments.target.findNoCase( "/app/cards/" ) == 1 ) return $r( "notifications.openCard" );
		if ( arguments.target == "/app/members" ) return $r( "notifications.viewMembers" );
		if ( arguments.target == "/app/profile" ) return $r( "notifications.viewProfile" );
		return $r( "notifications.viewBoards" );
	};

	notificationSummary = replace(
		$r( "notifications.summary" ),
		"{count}",
		toString( notificationTotal ),
		"all"
	);
	notificationPaginationStatus = replace(
		replace(
			$r( "notifications.pagination.status" ),
			"{page}",
			toString( notificationCurrentPage ),
			"all"
		),
		"{total}",
		toString( notificationTotalPages ),
		"all"
	);
</cfscript>
<cfoutput>
<section id="notification-list" class="notification-center" aria-live="polite" aria-busy="false">
	<header class="notification-toolbar">
		<div>
			<nav class="notification-filters" aria-label="#encodeForHTMLAttribute( $r( 'notifications.filter.label' ) )#">
				<cfloop list="all,unread" item="availableNotificationFilter">
					<a class="#notificationFilter == availableNotificationFilter ? 'active' : ''#"
						href="/app/notifications?filter=#encodeForURL( availableNotificationFilter )#"
						hx-get="/app/notifications?filter=#encodeForURL( availableNotificationFilter )#"
						hx-target="##notification-list"
						hx-select="##notification-list"
						hx-swap="outerHTML"
						hx-push-url="true"
						hx-indicator="##notification-list-loading"
						hx-sync="closest ##notification-list:replace"
						#notificationFilter == availableNotificationFilter ? 'aria-current="page"' : ''#>
						#$r( "notifications.filter.#availableNotificationFilter#" )#
						<cfif availableNotificationFilter == "unread"><span>#notificationUnreadCount#</span></cfif>
					</a>
				</cfloop>
			</nav>
			<p>#encodeForHTML( notificationSummary )#</p>
		</div>
		<cfif notificationUnreadCount>
			<form method="post" action="/app/notifications/read-all"
				hx-post="/app/notifications/read-all"
				hx-target="##notification-list"
				hx-select="##notification-list"
				hx-swap="outerHTML"
				hx-indicator="##notification-list-loading"
				hx-disabled-elt="find button">
				<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.notificationCsrfToken )#">
				<input type="hidden" name="filter" value="#encodeForHTMLAttribute( notificationFilter )#">
				<button class="button button-ghost button-small" type="submit">
					<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##list-checks"></use></svg>
					#$r( "notifications.markAllRead" )#
				</button>
			</form>
		</cfif>
		<span id="notification-list-loading" class="notification-list-loading" role="status" aria-live="polite">
			<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bell"></use></svg>
			#$r( "notifications.loading" )#
		</span>
	</header>

	<cfif notificationNotice.len()>
		<div class="form-success notification-notice">#$r( "notifications.notice.#notificationNotice#" )#</div>
	</cfif>
	<cfif notificationError.len()>
		<div class="form-errors notification-notice" role="alert">
			<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg>
			<p>#$r( "notifications.error.#notificationError#" )#</p>
		</div>
	</cfif>

	<cfif !notificationItems.len()>
		<div class="notification-empty-state">
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###notificationFilter == 'unread' ? 'check' : 'bell'#"></use></svg></span>
			<h2>#$r( "notifications.empty.#notificationFilter#.title" )#</h2>
			<p>#$r( "notifications.empty.#notificationFilter#.body" )#</p>
		</div>
	<cfelse>
		<div class="notification-items">
			<cfloop array="#notificationItems#" item="notificationItem">
				<cfset itemEventType=notificationEventType( notificationItem )>
				<cfset itemEventIcon=notificationEventIcon( itemEventType )>
				<cfset itemIsRead=( notificationItem.isRead ?: len( notificationItem.readAt ?: "" ) )>
				<cfset itemMessage=notificationEventMessage( notificationItem, itemEventType )>
				<cfset itemActionUrl=notificationActionUrl( notificationItem )>
				<cfset itemNavigationUrl=itemActionUrl.len() ? notificationNavigationUrl( itemActionUrl ) : "">
				<cfset itemActionLabel=itemActionUrl.len() ? notificationActionLabel( itemActionUrl ) : "">
				<article class="notification-item #itemIsRead ? 'is-read' : 'is-unread'#">
					<div class="notification-event-icon icon-#encodeForHTMLAttribute( itemEventType )#">
						<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###itemEventIcon#"></use></svg>
					</div>
					<div class="notification-item-content">
						<cfif !itemIsRead><span class="sr-only">#$r( "notifications.unreadLabel" )#</span></cfif>
						<p>#encodeForHTML( itemMessage )#</p>
						<div class="notification-location">
							<cfif len( notificationItem.boardName ?: "" )>
								<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg>#encodeForHTML( notificationItem.boardName )#</span>
							</cfif>
							<cfif len( notificationItem.laneName ?: "" )>
								<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>#encodeForHTML( notificationItem.laneName )#</span>
							</cfif>
						</div>
						<time datetime="#encodeForHTMLAttribute( notificationItem.createdAt ?: '' )#">#encodeForHTML( notificationDateLabel( notificationItem.createdAt ?: '' ) )#</time>
					</div>
					<div class="notification-item-actions">
						<cfif itemActionUrl.len()>
							<cfif itemIsRead>
								<a class="button button-ghost button-small"
									href="#encodeForHTMLAttribute( itemNavigationUrl )#"
									hx-get="#encodeForHTMLAttribute( itemNavigationUrl )#"
									hx-target="##workspace-main"
									hx-select="##workspace-main"
									hx-swap="outerHTML show:top"
									hx-push-url="true">
									#encodeForHTML( itemActionLabel )#
									<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>
								</a>
							<cfelse>
								<form method="post" action="/app/notifications/#encodeForURL( notificationItem.id )#/read"
									data-notification-open
									hx-post="/app/notifications/#encodeForURL( notificationItem.id )#/read"
									hx-target="##workspace-main"
									hx-select="##workspace-main"
									hx-swap="outerHTML show:top"
									hx-push-url="true"
									hx-disabled-elt="find button">
									<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.notificationCsrfToken )#">
									<input type="hidden" name="openTarget" value="1">
									<input type="hidden" name="filter" value="#encodeForHTMLAttribute( notificationFilter )#">
									<input type="hidden" name="page" value="#notificationCurrentPage#">
									<button class="button button-ghost button-small" type="submit">
										#encodeForHTML( itemActionLabel )#
										<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>
									</button>
								</form>
							</cfif>
						</cfif>
						<cfif !itemIsRead>
							<form method="post" action="/app/notifications/#encodeForURL( notificationItem.id )#/read"
								hx-post="/app/notifications/#encodeForURL( notificationItem.id )#/read"
								hx-target="##notification-list"
								hx-select="##notification-list"
								hx-swap="outerHTML"
								hx-indicator="##notification-list-loading"
								hx-disabled-elt="find button">
								<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.notificationCsrfToken )#">
								<input type="hidden" name="filter" value="#encodeForHTMLAttribute( notificationFilter )#">
								<input type="hidden" name="page" value="#notificationCurrentPage#">
								<button class="notification-mark-read" type="submit" title="#encodeForHTMLAttribute( $r( 'notifications.markRead' ) )#">
									<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg>
									<span class="sr-only">#$r( "notifications.markRead" )#</span>
								</button>
							</form>
						</cfif>
					</div>
				</article>
			</cfloop>
		</div>
	</cfif>

	<cfif notificationTotalPages gt 1>
		<nav class="notification-pagination" aria-label="#encodeForHTMLAttribute( $r( 'notifications.pagination.label' ) )#">
			<cfif notificationCurrentPage gt 1>
				<a class="button button-ghost button-small"
					href="/app/notifications?filter=#encodeForURL( notificationFilter )#&page=#notificationCurrentPage-1#"
					hx-get="/app/notifications?filter=#encodeForURL( notificationFilter )#&page=#notificationCurrentPage-1#"
					hx-target="##notification-list"
					hx-select="##notification-list"
					hx-swap="outerHTML show:top"
					hx-push-url="true"
					hx-indicator="##notification-list-loading">
					<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg>
					#$r( "notifications.pagination.previous" )#
				</a>
			<cfelse>
				<span></span>
			</cfif>
			<strong>#encodeForHTML( notificationPaginationStatus )#</strong>
			<cfif notificationCurrentPage lt notificationTotalPages>
				<a class="button button-ghost button-small"
					href="/app/notifications?filter=#encodeForURL( notificationFilter )#&page=#notificationCurrentPage+1#"
					hx-get="/app/notifications?filter=#encodeForURL( notificationFilter )#&page=#notificationCurrentPage+1#"
					hx-target="##notification-list"
					hx-select="##notification-list"
					hx-swap="outerHTML show:top"
					hx-push-url="true"
					hx-indicator="##notification-list-loading">
					#$r( "notifications.pagination.next" )#
					<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>
				</a>
			<cfelse>
				<span></span>
			</cfif>
		</nav>
	</cfif>

	<cfif prc.notificationBadgeOob ?: false>
		#view( "app/_notificationBadge" )#
	</cfif>
</section>
</cfoutput>
