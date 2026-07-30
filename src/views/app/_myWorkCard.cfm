<cfscript>
	locale = getFWLocale();
	dueMask = locale == "pt_BR" ? "dd/MM/yyyy" : "MMM d, yyyy";
	canEditMyWork = prc.auth.role != "viewer";
</cfscript>
<cfoutput>
<article class="my-work-card priority-border-#encodeForHTMLAttribute( card.priority )#" data-my-work-card="#encodeForHTMLAttribute( card.id )#" data-my-work-group="#encodeForHTMLAttribute( card.bucket )#" data-priority="#encodeForHTMLAttribute( card.priority )#" data-board-id="#encodeForHTMLAttribute( card.board_id )#">
	<div class="my-work-card-content">
		<div class="my-work-card-location">
			<span class="column-dot dot-#encodeForHTMLAttribute( card.column_color )#"></span>
			<span>#encodeForHTML( card.board_name )#</span>
			<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>
			<span>#encodeForHTML( card.column_name )#</span>
		</div>
		<h3><a href="/app/cards/#encodeForURL( card.id )#?returnTo=my-work" hx-get="/app/cards/#encodeForURL( card.id )#?returnTo=my-work" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true">#encodeForHTML( card.title )#</a></h3>
		<cfif len( trim( card.description ?: "" ) )><p>#encodeForHTML( card.description )#</p></cfif>
		<cfif len( card.labels_csv ?: "" )><div class="card-labels"><cfloop list="#card.labels_csv#" item="label"><span>#encodeForHTML( label )#</span></cfloop></div></cfif>
		<div class="my-work-card-badges">
			<span class="priority-chip priority-#encodeForHTMLAttribute( card.priority )#">#$r( "card.priority.#card.priority#" )#</span>
			<cfif card.bucket == "completed">
				<span class="my-work-due-badge completed"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg>#$r( "myWork.completed" )#</span>
			<cfelseif !isNull( card.due_at )>
				<span class="my-work-due-badge #card.bucket == 'overdue' ? 'overdue' : card.bucket == 'today' ? 'today' : ''#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg>#encodeForHTML( dateFormat( card.due_at, dueMask ) )#</span>
			<cfelse>
				<span class="my-work-due-badge"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg>#$r( "myWork.noDue" )#</span>
			</cfif>
		</div>
	</div>
	<form class="my-work-quick-form" method="post" action="/app/my-work/cards/#encodeForURL( card.id )#"
		hx-post="/app/my-work/cards/#encodeForURL( card.id )#"
		hx-target="##my-work-results"
		hx-select="##my-work-results"
		hx-swap="outerHTML"
		hx-disabled-elt="find button">
		<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.myWorkCsrfToken )#">
		<input type="hidden" name="version" value="#card.version#">
		<input type="hidden" name="query" value="#encodeForHTMLAttribute( filters.query )#">
		<input type="hidden" name="boardId" value="#encodeForHTMLAttribute( filters.boardId )#">
		<input type="hidden" name="due" value="#encodeForHTMLAttribute( filters.due )#">
		<input type="hidden" name="sort" value="#encodeForHTMLAttribute( filters.sort )#">
		<input type="hidden" name="filterPriority" value="#encodeForHTMLAttribute( filters.priority )#">
		<label><span>#$r( "card.priority" )#</span><select name="priority" #canEditMyWork ? "" : "disabled"#><cfloop list="none,low,medium,high,urgent" item="priority"><option value="#priority#" #card.priority == priority ? "selected" : ""#>#$r( "card.priority.#priority#" )#</option></cfloop></select></label>
		<label><span>#$r( "card.dueDate" )#</span><input name="dueDate" type="date" value="#encodeForHTMLAttribute( card.due_date ?: "" )#" #canEditMyWork ? "" : "disabled"#></label>
		<cfif canEditMyWork><button type="submit" aria-label="#encodeForHTMLAttribute( $r( 'myWork.quickSave' ) )#" title="#encodeForHTMLAttribute( $r( 'myWork.quickSave' ) )#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg></button></cfif>
	</form>
</article>
</cfoutput>
