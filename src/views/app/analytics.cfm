<cfscript>
	analyticsOptions = prc.analyticsOptions ?: { found=true,code="ok",boards=[],members=[] };
	analyticsFilters = prc.analyticsFilters ?: {
		fromDate="",
		toDate="",
		boardId="",
		assigneeId=""
	};
	analyticsBoards = analyticsOptions.boards ?: [];
	analyticsMembers = analyticsOptions.members ?: [];
	analyticsTimezone = prc.analytics.period.timezone ?: "UTC";
</cfscript>
<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
<section id="workspace-main" class="workspace-main analytics-main" data-workspace-page="analytics">
	<header class="workspace-header analytics-header">
		<div>
			<small>#$r( "analytics.eyebrow" )#</small>
			<h1>#$r( "analytics.title" )#</h1>
			<p>#$r( "analytics.body" )#</p>
		</div>
	</header>

	<form class="analytics-filters" method="get" action="/app/analytics"
		data-analytics-filters
		data-error-generic="#encodeForHTMLAttribute( $r( 'analytics.error.generic' ) )#"
		hx-get="/app/analytics"
		hx-target="##analytics-results"
		hx-select="##analytics-results"
		hx-swap="outerHTML"
		hx-replace-url="true"
		hx-sync="this:replace"
		hx-indicator="##analytics-loading"
		hx-disabled-elt="find button">
		<label>
			<span>#$r( "analytics.filter.from" )#</span>
			<input name="fromDate" type="date" value="#encodeForHTMLAttribute( analyticsFilters.fromDate ?: '' )#">
		</label>
		<label>
			<span>#$r( "analytics.filter.to" )#</span>
			<input name="toDate" type="date" value="#encodeForHTMLAttribute( analyticsFilters.toDate ?: '' )#">
		</label>
		<label>
			<span>#$r( "analytics.filter.board" )#</span>
			<select name="boardId">
				<option value="">#$r( "analytics.filter.allBoards" )#</option>
				<cfloop array="#analyticsBoards#" item="analyticsBoard">
					<option value="#encodeForHTMLAttribute( analyticsBoard.id )#" #( analyticsFilters.boardId ?: "" ) == analyticsBoard.id ? "selected" : ""#>#encodeForHTML( analyticsBoard.name )#</option>
				</cfloop>
			</select>
		</label>
		<label>
			<span>#$r( "analytics.filter.assignee" )#</span>
			<select name="assigneeId">
				<option value="">#$r( "analytics.filter.allAssignees" )#</option>
				<cfloop array="#analyticsMembers#" item="analyticsMember">
					<option value="#encodeForHTMLAttribute( analyticsMember.id )#" #( analyticsFilters.assigneeId ?: "" ) == analyticsMember.id ? "selected" : ""#>#encodeForHTML( analyticsMember.displayName )#</option>
				</cfloop>
			</select>
		</label>
		<div class="analytics-filter-actions">
			<button class="button button-primary button-small" type="submit">
				<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##filter"></use></svg>
				#$r( "analytics.filter.apply" )#
			</button>
			<a class="button button-ghost button-small" href="/app/analytics"
				hx-get="/app/analytics"
				hx-target="##workspace-main"
				hx-select="##workspace-main"
				hx-swap="outerHTML show:top"
				hx-push-url="true">
				<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##close"></use></svg>
				#$r( "analytics.filter.clear" )#
			</a>
		</div>
		<p class="analytics-filter-help">#$r( "analytics.filter.maxRange" )# &middot; #$r( "analytics.filter.timezone" )#: #encodeForHTML( analyticsTimezone )#</p>
		<span id="analytics-loading" class="analytics-loading" role="status" aria-live="polite">
			<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg>
			#$r( "analytics.loading" )#
		</span>
	</form>

	<div class="analytics-client-error" data-analytics-client-error role="alert" hidden>
		<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg>
		<p>#$r( "analytics.error.generic" )#</p>
	</div>

	#view( "app/_analyticsResults" )#
</section>
</cfoutput>
