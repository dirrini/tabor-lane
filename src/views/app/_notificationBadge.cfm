<cfscript>
	notificationUnreadCount = max( 0, val( prc.notificationUnreadCount ?: 0 ) );
	notificationBadgeText = notificationUnreadCount > 99 ? "99+" : toString( notificationUnreadCount );
	notificationBadgeLabel = replace(
		$r( "notifications.badge.label" ),
		"{count}",
		toString( notificationUnreadCount ),
		"all"
	);
	notificationBadgeOobAttribute = ( prc.notificationBadgeOob ?: false )
		? ' hx-swap-oob="outerHTML"'
		: "";
	notificationBadgeHiddenAttribute = notificationUnreadCount ? "" : " hidden";
</cfscript>
<cfoutput><span id="notification-badge" class="notification-badge"#notificationBadgeOobAttribute##notificationBadgeHiddenAttribute# aria-label="#encodeForHTMLAttribute( notificationBadgeLabel )#">#encodeForHTML( notificationBadgeText )#</span></cfoutput>
