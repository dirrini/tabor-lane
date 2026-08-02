<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
<section id="workspace-main" class="workspace-main automations-main" data-workspace-page="automations">
	<header class="workspace-header automations-header">
		<div>
			<small>#$r( "automations.eyebrow" )#</small>
			<h1>#$r( "automations.title" )#</h1>
			<p>#$r( "automations.body" )#</p>
		</div>
	</header>

	#view( "app/_automationPanel" )#
</section>
</cfoutput>
