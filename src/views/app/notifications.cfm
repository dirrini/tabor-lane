<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
<section id="workspace-main" class="workspace-main notifications-main" data-workspace-page="notifications">
	<header class="workspace-header notifications-header">
		<div>
			<small>#$r( "notifications.eyebrow" )#</small>
			<h1>#$r( "notifications.title" )#</h1>
			<p>#$r( "notifications.body" )#</p>
		</div>
	</header>

	#view( "app/_notificationList" )#
</section>
</cfoutput>
