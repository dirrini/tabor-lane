<cfscript>
	myWork = prc.myWork;
	filters = myWork.filters;
	groupOrder = [ "overdue", "today", "upcoming", "no_due", "completed" ];
	errorKey = listFindNoCase( "invalid,forbidden,read_only,conflict", prc.error ?: "" ) ? prc.error : "generic";
</cfscript>
<cfoutput>
<section id="my-work-results" class="my-work-results" aria-live="polite">
	<div class="my-work-summary">
		<article>
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##list-checks"></use></svg></span>
			<div><strong>#myWork.summary.total#</strong><small>#$r( "myWork.summary.total" )#</small></div>
		</article>
		<article class="#val( myWork.summary.overdue ) ? 'attention' : ''#">
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg></span>
			<div><strong>#myWork.summary.overdue#</strong><small>#$r( "myWork.summary.overdue" )#</small></div>
		</article>
		<article>
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg></span>
			<div><strong>#myWork.summary.today#</strong><small>#$r( "myWork.summary.today" )#</small></div>
		</article>
		<article class="complete">
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg></span>
			<div><strong>#myWork.summary.completed#</strong><small>#$r( "myWork.summary.completed" )#</small></div>
		</article>
	</div>

	<cfif ( prc.notice ?: "" ) == "saved">
		<div class="form-success my-work-notice">#$r( "myWork.saved" )#</div>
	</cfif>
	<cfif len( prc.error ?: "" )>
		<div class="form-errors my-work-notice"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "myWork.error.#errorKey#" )#</p></div>
	</cfif>

	<cfif !myWork.cards.len()>
		<div class="my-work-empty">
			<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###myWork.hasFilters ? 'search' : 'list-checks'#"></use></svg>
			<h2>#$r( myWork.hasFilters ? "myWork.empty.filteredTitle" : "myWork.empty.title" )#</h2>
			<p>#$r( myWork.hasFilters ? "myWork.empty.filteredBody" : "myWork.empty.body" )#</p>
			<cfif myWork.hasFilters><a class="button button-ghost button-small" href="/app/my-work?resetFilters=1" hx-get="/app/my-work?resetFilters=1" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true">#$r( "myWork.filter.clear" )#</a></cfif>
		</div>
	<cfelse>
		<div class="my-work-groups">
			<cfloop array="#groupOrder#" item="bucket">
				<cfif myWork.groups[ bucket ].len()>
					<section class="my-work-group group-#encodeForHTMLAttribute( bucket )#" data-my-work-group="#encodeForHTMLAttribute( bucket )#">
						<header>
							<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###bucket == 'overdue' ? 'alert' : bucket == 'completed' ? 'check' : 'clock'#"></use></svg></span>
							<div><h2>#$r( "myWork.group.#bucket#" )#</h2><p>#$r( "myWork.group.#bucket#.body" )#</p></div>
							<b>#myWork.groups[ bucket ].len()#</b>
						</header>
						<div class="my-work-card-list">
							<cfloop array="#myWork.groups[ bucket ]#" item="card">
								<cfinclude template="_myWorkCard.cfm">
							</cfloop>
						</div>
					</section>
				</cfif>
			</cfloop>
		</div>
	</cfif>
</section>
</cfoutput>
