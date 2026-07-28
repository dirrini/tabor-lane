<cfoutput>
<main class="workspace-shell" data-workspace data-csrf-token="#encodeForHTMLAttribute( prc.cardCsrfToken )#" data-move-success="#encodeForHTMLAttribute( $r( 'app.card.moved' ) )#" data-move-error="#encodeForHTMLAttribute( $r( 'app.card.moveError' ) )#">
    <aside class="workspace-sidebar">
        <a class="brand" href="/">
            <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
            <span class="brand-name">Tabor<span>Lane</span></span>
        </a>
        <div class="workspace-picker">
            <span class="workspace-avatar">#encodeForHTML( left( prc.auth.workspaceName, 1 ) )#</span>
            <div><small>#$r( "app.workspace" )#</small><strong>#encodeForHTML( prc.auth.workspaceName )#</strong></div>
            <b><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chevron-down"></use></svg></b>
        </div>
        <nav>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##home"></use></svg></span>#$r( "app.myWork" )#</a>
            <a href="/app" class="active"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg></span>#$r( "app.boards" )#</a>
            <a href="/app/members"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg></span>#$r( "members.nav" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg></span>#$r( "app.analytics" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg></span>#$r( "app.automations" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##settings"></use></svg></span>#$r( "app.settings" )#</a>
        </nav>
        <a class="workspace-account" href="/app/profile">
            <span class="workspace-avatar account-avatar">#encodeForHTML( left( prc.auth.displayName, 1 ) )#</span>
            <div><strong>#encodeForHTML( prc.auth.displayName )#</strong><small>#encodeForHTML( prc.auth.role )# · #encodeForHTML( prc.auth.email )#</small></div>
        </a>
        <form method="post" action="/auth/logout">
            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.logoutCsrfToken )#">
            <button class="workspace-back" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "app.logout" )#</button>
        </form>
    </aside>

    <section class="workspace-main">
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
                            <cfif !isNull( column.wip_limit )><em>WIP #column.cards.len()# / #column.wip_limit#</em></cfif>
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
</main>
</cfoutput>
