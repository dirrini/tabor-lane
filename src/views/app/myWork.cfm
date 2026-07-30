<cfscript>
	filters = prc.myWork.filters;
</cfscript>
<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
<section id="workspace-main" class="workspace-main my-work-main" data-workspace-page="myWork">
	<header class="workspace-header my-work-header">
		<div>
			<small>#$r( "myWork.eyebrow" )#</small>
			<h1>#$r( "myWork.title" )#</h1>
			<p>#$r( "myWork.body" )#</p>
		</div>
		<span class="avatar account-avatar">#encodeForHTML( left( prc.auth.displayName, 1 ) )#</span>
	</header>

	<form class="my-work-filters" method="get" action="/app/my-work"
		hx-get="/app/my-work"
		hx-trigger="submit, input changed delay:350ms from:input[name='query'], change from:select"
		hx-target="##my-work-results"
		hx-select="##my-work-results"
		hx-swap="outerHTML"
		hx-replace-url="true"
		hx-sync="this:replace">
		<label class="my-work-search">
			<span>#$r( "myWork.filter.search" )#</span>
			<i><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##search"></use></svg></i>
			<input name="query" type="search" maxlength="100" value="#encodeForHTMLAttribute( filters.query )#" placeholder="#encodeForHTMLAttribute( $r( 'myWork.filter.searchPlaceholder' ) )#">
		</label>
		<label>
			<span>#$r( "myWork.filter.board" )#</span>
			<select name="boardId">
				<option value="">#$r( "myWork.filter.allBoards" )#</option>
				<cfloop array="#prc.myWork.boards#" item="board">
					<option value="#encodeForHTMLAttribute( board.id )#" #filters.boardId == board.id ? "selected" : ""#>#encodeForHTML( board.name )# (#board.assigned_count#)</option>
				</cfloop>
			</select>
		</label>
		<label>
			<span>#$r( "myWork.filter.due" )#</span>
			<select name="due">
				<cfloop list="all,overdue,today,upcoming,no_due,completed" item="dueFilter">
					<option value="#dueFilter#" #filters.due == dueFilter ? "selected" : ""#>#$r( "myWork.filter.due.#dueFilter#" )#</option>
				</cfloop>
			</select>
		</label>
		<label>
			<span>#$r( "card.priority" )#</span>
			<select name="priority">
				<option value="">#$r( "myWork.filter.allPriorities" )#</option>
				<cfloop list="none,low,medium,high,urgent" item="priority">
					<option value="#priority#" #filters.priority == priority ? "selected" : ""#>#$r( "card.priority.#priority#" )#</option>
				</cfloop>
			</select>
		</label>
		<label>
			<span>#$r( "myWork.filter.sort" )#</span>
			<select name="sort">
				<cfloop list="due,priority,updated" item="sortOption">
					<option value="#sortOption#" #filters.sort == sortOption ? "selected" : ""#>#$r( "myWork.filter.sort.#sortOption#" )#</option>
				</cfloop>
			</select>
		</label>
		<div class="my-work-filter-actions">
			<button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##filter"></use></svg>#$r( "myWork.filter.apply" )#</button>
			<a class="button button-ghost button-small" href="/app/my-work" hx-get="/app/my-work" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##close"></use></svg>#$r( "myWork.filter.clear" )#</a>
		</div>
	</form>

	#view( "app/_myWorkResults" )#
</section>
</cfoutput>
