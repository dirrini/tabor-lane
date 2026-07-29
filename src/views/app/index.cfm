<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
    <section id="workspace-main" class="workspace-main" data-workspace-page="app" data-workspace data-csrf-token="#encodeForHTMLAttribute( prc.cardCsrfToken )#" data-move-success="#encodeForHTMLAttribute( $r( 'app.card.moved' ) )#" data-move-error="#encodeForHTMLAttribute( $r( 'app.card.moveError' ) )#">
        <cfif !prc.workspaceBoard.found>
            <div class="app-empty-state"><svg class="icon"><use href="/resources/icons.svg##board"></use></svg><h1>#$r( "app.empty.title" )#</h1><p>#$r( "app.empty.body" )#</p></div>
        <cfelse>
            <header class="workspace-header">
                <div>
                    <small>#encodeForHTML( prc.workspaceBoard.board.workspace_name )# · #encodeForHTML( uCase( prc.workspaceBoard.board.plan ) )#</small>
                    <h1>#encodeForHTML( prc.workspaceBoard.board.name )#</h1>
                </div>
                <div>
                    <span class="avatar account-avatar">#encodeForHTML( left( prc.auth.displayName, 1 ) )#</span>
                    <button class="button button-primary button-small" type="button" data-card-form-toggle>
                        <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "app.newCard" )#
                    </button>
                </div>
            </header>

            <form class="quick-card-form" method="post" action="/app/cards" data-card-form hidden>
                <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.cardCsrfToken )#">
                <label><span>#$r( "app.card.title" )#</span><input name="title" type="text" required maxlength="255" placeholder="#encodeForHTMLAttribute( $r( 'app.card.titlePlaceholder' ) )#"></label>
                <label><span>#$r( "app.card.description" )#</span><input name="description" type="text" maxlength="500" placeholder="#encodeForHTMLAttribute( $r( 'app.card.descriptionPlaceholder' ) )#"></label>
                <label><span>#$r( "app.card.column" )#</span>
                    <select name="columnId" required>
                        <cfloop array="#prc.workspaceBoard.columns#" item="column"><option value="#encodeForHTMLAttribute( column.id )#">#encodeForHTML( column.name )#</option></cfloop>
                    </select>
                </label>
                <div><button class="button button-primary button-small" type="submit">#$r( "app.card.create" )#</button><button class="button button-ghost button-small" type="button" data-card-form-cancel>#$r( "app.card.cancel" )#</button></div>
            </form>

            <div class="workspace-board kanban-grid">
                <cfloop array="#prc.workspaceBoard.columns#" item="column" index="columnIndex">
                    <article class="kanban-column live-column" data-column-id="#encodeForHTMLAttribute( column.id )#">
                        <header>
                            <span class="column-dot dot-#columnIndex == 1 ? 'sand' : columnIndex == 2 ? 'blue' : columnIndex == 3 ? 'amber' : 'green'#"></span>
                            <strong>#encodeForHTML( column.name )#</strong>
                            <b data-card-count>#column.cards.len()#</b>
                            <cfif !isNull( column.wip_limit )><em>WIP <span data-wip-count>#column.cards.len()#</span> / #column.wip_limit#</em></cfif>
                        </header>
                        <div class="live-card-list" data-card-list>
                            <cfloop array="#column.cards#" item="card">
                                <article class="demo-card live-card" draggable="true" data-card-id="#encodeForHTMLAttribute( card.id )#">
                                    <h3>#encodeForHTML( card.title )#</h3>
                                    <cfif len( trim( card.description ?: "" ) )><p>#encodeForHTML( card.description )#</p></cfif>
                                    <div class="card-meta"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##more"></use></svg></span><i class="avatar account-avatar">#encodeForHTML( left( prc.auth.displayName, 1 ) )#</i></div>
                                </article>
                            </cfloop>
                            <p class="column-empty" data-column-empty #column.cards.len() ? "hidden" : ""#>#$r( "app.column.empty" )#</p>
                        </div>
                    </article>
                </cfloop>
            </div>
            <div class="board-toast" role="status" aria-live="polite" data-board-toast></div>
        </cfif>
    </section>
</cfoutput>
