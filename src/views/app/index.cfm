<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
    <section id="workspace-main" class="workspace-main" data-workspace-page="app" data-workspace data-board-id="#prc.workspaceBoard.found ? encodeForHTMLAttribute( prc.workspaceBoard.board.id ) : ''#" data-csrf-token="#encodeForHTMLAttribute( prc.cardCsrfToken )#" data-move-success="#encodeForHTMLAttribute( $r( 'app.card.moved' ) )#" data-move-error="#encodeForHTMLAttribute( $r( 'app.card.moveError' ) )#" data-layout-saved="#encodeForHTMLAttribute( $r( 'app.lane.layoutSaved' ) )#" data-layout-error="#encodeForHTMLAttribute( $r( 'app.lane.layoutError' ) )#">
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
                    <cfif listFindNoCase("owner,admin",prc.workspaceBoard.board.role)><a class="button button-ghost button-small" href="/app/boards/manage?boardId=#encodeForURL(prc.workspaceBoard.board.id)#" hx-get="/app/boards/manage?boardId=#encodeForURL(prc.workspaceBoard.board.id)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##settings"></use></svg> #$r("boards.manage")#</a></cfif>
                    <cfif prc.workspaceBoard.board.role != "viewer"><button class="button button-primary button-small" type="button" data-card-form-toggle>
                        <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "app.newCard" )#
                    </button></cfif>
                </div>
            </header>

            <cfif prc.workspaceBoard.boards.len() gt 1>
                <nav class="board-switcher" aria-label="#encodeForHTMLAttribute($r('boards.active'))#">
                    <cfloop array="#prc.workspaceBoard.boards#" item="workspaceBoard"><a class="#workspaceBoard.id==prc.workspaceBoard.board.id ? 'active' : ''#" href="/app?boardId=#encodeForURL(workspaceBoard.id)#" hx-get="/app?boardId=#encodeForURL(workspaceBoard.id)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg>#encodeForHTML(workspaceBoard.name)#</a></cfloop>
                </nav>
            </cfif>

            <cfif prc.workspaceBoard.board.role != "viewer"><form class="quick-card-form" method="post" action="/app/cards" data-card-form hidden>
                <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.cardCsrfToken )#">
                <label><span>#$r( "app.card.title" )#</span><input name="title" type="text" required maxlength="255" placeholder="#encodeForHTMLAttribute( $r( 'app.card.titlePlaceholder' ) )#"></label>
                <label><span>#$r( "app.card.description" )#</span><input name="description" type="text" maxlength="500" placeholder="#encodeForHTMLAttribute( $r( 'app.card.descriptionPlaceholder' ) )#"></label>
                <label><span>#$r( "app.card.column" )#</span>
                    <select name="columnId" required>
                        <cfloop array="#prc.workspaceBoard.columns#" item="column"><option value="#encodeForHTMLAttribute( column.id )#">#encodeForHTML( column.name )#</option></cfloop>
                    </select>
                </label>
                <div><button class="button button-primary button-small" type="submit">#$r( "app.card.create" )#</button><button class="button button-ghost button-small" type="button" data-card-form-cancel>#$r( "app.card.cancel" )#</button></div>
            </form></cfif>

            <div class="workspace-board kanban-grid">
                <cfloop array="#prc.workspaceBoard.columns#" item="column" index="columnIndex">
                    <article class="kanban-column live-column#column.is_collapsed ? ' is-collapsed' : ''#" data-column-id="#encodeForHTMLAttribute( column.id )#" data-lane-width="#column.width_px#" data-lane-collapsed="#column.is_collapsed ? 'true' : 'false'#" style="--lane-width:#column.width_px#px">
                        <header>
                            <span class="lane-heading">
                                <span class="column-dot dot-#encodeForHTMLAttribute(column.color)#"></span>
                                <strong>#encodeForHTML( column.name )#</strong>
                                <b data-card-count>#column.cards.len()#</b>
                                <cfif !isNull( column.wip_limit )><em>WIP <span data-wip-count>#column.cards.len()#</span> / #column.wip_limit#</em></cfif>
                            </span>
                            <button class="lane-collapse-button" type="button" data-lane-collapse aria-label="#encodeForHTMLAttribute( column.is_collapsed ? $r( 'app.lane.expand' ) : $r( 'app.lane.collapse' ) )#" title="#encodeForHTMLAttribute( column.is_collapsed ? $r( 'app.lane.expand' ) : $r( 'app.lane.collapse' ) )#" data-collapse-label="#encodeForHTMLAttribute( $r( 'app.lane.collapse' ) )#" data-expand-label="#encodeForHTMLAttribute( $r( 'app.lane.expand' ) )#">
                                <svg class="icon lane-collapse-icon" aria-hidden="true"><use href="/resources/icons.svg###column.is_collapsed ? 'expand-horizontal' : 'collapse-horizontal'#"></use></svg>
                            </button>
                        </header>
                        <div class="live-card-list" data-card-list>
                            <cfloop array="#column.cards#" item="card">
                                <article class="demo-card live-card priority-border-#encodeForHTMLAttribute( card.priority )#" draggable="#prc.workspaceBoard.board.role != 'viewer'#" data-card-id="#encodeForHTMLAttribute( card.id )#" data-card-title="#encodeForHTMLAttribute( card.title )#">
                                    <h3><a href="/app/cards/#encodeForURL(card.id)#" hx-get="/app/cards/#encodeForURL(card.id)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true">#encodeForHTML( card.title )#</a></h3>
                                    <cfif len( trim( card.description ?: "" ) )><p>#encodeForHTML( card.description )#</p></cfif>
                                    <cfif len( card.labels_csv ?: "" )><div class="card-labels"><cfloop list="#card.labels_csv#" item="label"><span>#encodeForHTML( label )#</span></cfloop></div></cfif>
                                    <div class="card-meta">
                                        <span class="card-meta-items">
                                            <cfif !isNull( card.due_at )><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg> #encodeForHTML( dateFormat( card.due_at, getFWLocale() == "pt_BR" ? "dd/MM" : "mmm d" ) )#</span></cfif>
                                            <cfif val( card.attachment_count ?: 0 )>
                                                <span class="card-attachment-indicator" tabindex="0" aria-describedby="card-attachments-#encodeForHTMLAttribute( card.id )#" data-card-attachments>
                                                    <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##paperclip"></use></svg>
                                                    <span class="card-attachment-tooltip" id="card-attachments-#encodeForHTMLAttribute( card.id )#" role="tooltip">
                                                        <strong>#$r( "app.card.attachments" )#</strong>
                                                        <cfloop list="#card.attachment_names#" delimiters="#chr( 10 )#" item="attachmentName"><span>#encodeForHTML( attachmentName )#</span></cfloop>
                                                    </span>
                                                </span>
                                            </cfif>
                                        </span>
                                        <cfif len( card.assignee_name ?: "" )><i class="avatar account-avatar" title="#encodeForHTMLAttribute( card.assignee_name )#">#encodeForHTML( left( card.assignee_name, 1 ) )#</i></cfif>
                                    </div>
                                </article>
                            </cfloop>
                            <p class="column-empty" data-column-empty #column.cards.len() ? "hidden" : ""#>#$r( "app.column.empty" )#</p>
                        </div>
                        <div class="lane-resize-handle" role="separator" aria-orientation="vertical" aria-label="#encodeForHTMLAttribute( $r( 'app.lane.resize' ) )#" title="#encodeForHTMLAttribute( $r( 'app.lane.resize' ) )#" tabindex="0" data-lane-resize></div>
                    </article>
                </cfloop>
            </div>
            <div class="board-toast" role="status" aria-live="polite" data-board-toast></div>
        </cfif>
    </section>
</cfoutput>
