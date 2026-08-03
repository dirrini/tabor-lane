<cfset boardRealtimeEnabled=prc.workspaceBoard.found && compareNoCase( prc.workspaceBoard.board.plan, "premium" ) == 0>
<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
    <section id="workspace-main" class="workspace-main" data-workspace-page="app" data-board-viewport data-workspace data-board-id="#prc.workspaceBoard.found ? encodeForHTMLAttribute( prc.workspaceBoard.board.id ) : ''#" data-board-revision="#prc.workspaceBoard.found ? encodeForHTMLAttribute( prc.workspaceBoard.revision ) : ''#" data-board-revision-url="#prc.workspaceBoard.found ? '/app/boards/' & encodeForURL( prc.workspaceBoard.board.id ) & '/revision' : ''#" data-board-refresh-url="#prc.workspaceBoard.found ? '/app?boardId=' & encodeForURL( prc.workspaceBoard.board.id ) : '/app'#" data-board-realtime-enabled="#boardRealtimeEnabled ? 'true' : 'false'#" data-board-events-url="#boardRealtimeEnabled ? '/app/boards/' & encodeForURL( prc.workspaceBoard.board.id ) & '/events' : ''#" data-realtime-connecting="#encodeForHTMLAttribute( $r( 'app.board.liveSyncConnecting' ) )#" data-realtime-connected="#encodeForHTMLAttribute( $r( 'app.board.liveSyncConnected' ) )#" data-realtime-reconnecting="#encodeForHTMLAttribute( $r( 'app.board.liveSyncReconnecting' ) )#" data-csrf-token="#encodeForHTMLAttribute( prc.cardCsrfToken )#" data-move-success="#encodeForHTMLAttribute( $r( 'app.card.moved' ) )#" data-move-error="#encodeForHTMLAttribute( $r( 'app.card.moveError' ) )#" data-layout-saved="#encodeForHTMLAttribute( $r( 'app.lane.layoutSaved' ) )#" data-layout-error="#encodeForHTMLAttribute( $r( 'app.lane.layoutError' ) )#" data-viewed-now="#encodeForHTMLAttribute( $r( 'app.board.viewedNow' ) )#" data-viewed-minutes="#encodeForHTMLAttribute( $r( 'app.board.viewedMinutesAgo' ) )#" data-viewed-hours="#encodeForHTMLAttribute( $r( 'app.board.viewedHoursAgo' ) )#">
        <cfif !prc.workspaceBoard.found>
            <div class="app-empty-state"><svg class="icon"><use href="/resources/icons.svg##board"></use></svg><h1>#$r( "app.empty.title" )#</h1><p>#$r( "app.empty.body" )#</p></div>
        <cfelse>
            <header class="workspace-header">
                <div>
                    <small>#encodeForHTML( prc.workspaceBoard.board.workspace_name )# &middot; #encodeForHTML( uCase( prc.workspaceBoard.board.plan ) )#</small>
                    <h1>#encodeForHTML( prc.workspaceBoard.board.name )#</h1>
                </div>
                <div class="board-toolbar-actions">
                    <cfif boardRealtimeEnabled><span class="board-live-status is-connecting" data-board-realtime-status data-realtime-state="connecting" aria-live="polite" title="#encodeForHTMLAttribute( $r( 'app.board.liveSyncPremium' ) )#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg><span data-board-realtime-label>#$r( "app.board.liveSyncConnecting" )#</span></span></cfif>
                    <cfif !boardRealtimeEnabled><span class="board-viewed-status" aria-live="polite"><i aria-hidden="true"></i><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg><span data-board-viewed-label>#$r( "app.board.viewedNow" )#</span></span></cfif>
                    <cfif listFindNoCase("owner,admin",prc.workspaceBoard.board.role)><a class="button button-ghost button-small" href="/app/boards/manage?boardId=#encodeForURL(prc.workspaceBoard.board.id)#" hx-get="/app/boards/manage?boardId=#encodeForURL(prc.workspaceBoard.board.id)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##settings"></use></svg> #$r("boards.manage")#</a></cfif>
                    <cfif prc.workspaceBoard.board.role != "viewer"><button class="button button-primary button-small" type="button" data-card-form-toggle aria-expanded="false" aria-controls="quick-card-form">
                        <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "app.newCard" )#
                    </button></cfif>
                </div>
            </header>

            <section class="board-progress-panel" aria-label="#encodeForHTMLAttribute( $r( 'app.board.progress' ) )#">
                <div><span>#$r( "app.board.progress" )#</span><strong><b data-board-completed-count>#prc.workspaceBoard.completedCards#</b> / <b data-board-total-count>#prc.workspaceBoard.totalCards#</b> <span data-board-progress-label data-singular="#encodeForHTMLAttribute( $r( 'app.board.cardCompleted' ) )#" data-plural="#encodeForHTMLAttribute( $r( 'app.board.cardsCompleted' ) )#">#$r( prc.workspaceBoard.totalCards == 1 ? "app.board.cardCompleted" : "app.board.cardsCompleted" )#</span></strong></div>
                <span class="board-progress-track" role="progressbar" aria-label="#encodeForHTMLAttribute( $r( 'app.board.progress' ) )#" aria-valuemin="0" aria-valuemax="100" aria-valuenow="#prc.workspaceBoard.progressPercent#" data-board-progress><i style="width:#prc.workspaceBoard.progressPercent#%"></i></span>
            </section>

            <cfif prc.boardError.len()><div class="form-errors board-form-error"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "app.card.error.#prc.boardError#" )#</p></div></cfif>

            <cfif prc.workspaceBoard.boards.len() gt 1>
                <nav class="board-switcher" aria-label="#encodeForHTMLAttribute($r('boards.active'))#">
                    <cfloop array="#prc.workspaceBoard.boards#" item="workspaceBoard"><a class="#workspaceBoard.id==prc.workspaceBoard.board.id ? 'active' : ''#" href="/app?boardId=#encodeForURL(workspaceBoard.id)#" hx-get="/app?boardId=#encodeForURL(workspaceBoard.id)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg>#encodeForHTML(workspaceBoard.name)#</a></cfloop>
                </nav>
            </cfif>

            <cfif prc.workspaceBoard.board.role != "viewer"><form id="quick-card-form" class="quick-card-form" method="post" action="/app/cards" data-card-form hidden>
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
                    <cfset columnHiddenFromMembers=column.is_hidden_from_members ?: false>
                    <cfset wipValue=column.wip_limit ?: "">
                    <cfset hasWip=len( toString( wipValue ) ) && val( wipValue ) gt 0>
                    <cfset wipPercent=hasWip ? min( 100, round( column.cards.len() * 100 / val( wipValue ) ) ) : 0>
                    <cfset wipState=hasWip && column.cards.len() gte val( wipValue ) ? " is-at-limit" : hasWip && column.cards.len() * 100 / val( wipValue ) gte 75 ? " is-near-limit" : "">
                    <cfset wipAriaText=replace( replace( $r( "app.lane.wipValue" ), "{count}", column.cards.len() ), "{limit}", wipValue )>
                    <article class="kanban-column live-column#column.is_collapsed ? ' is-collapsed' : ''##columnHiddenFromMembers ? ' is-hidden-from-members' : ''#" data-column-id="#encodeForHTMLAttribute( column.id )#" data-lane-width="#column.width_px#" data-lane-collapsed="#column.is_collapsed ? 'true' : 'false'#" data-hidden-from-members="#columnHiddenFromMembers ? 'true' : 'false'#" data-completion-state="#encodeForHTMLAttribute( column.completion_state )#" style="--lane-width:#column.width_px#px">
                        <header>
                            <span class="lane-heading">
                                <span class="column-dot dot-#encodeForHTMLAttribute(column.color)#"></span>
                                <strong>#encodeForHTML( column.name )#</strong>
                                <cfif columnHiddenFromMembers && listFindNoCase("owner,admin",prc.workspaceBoard.board.role)><span class="lane-hidden-badge" title="#encodeForHTMLAttribute($r('lanes.hiddenHint'))#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg><span>#$r("lanes.hiddenBadge")#</span></span></cfif>
                                <b data-card-count>#column.cards.len()#</b>
                                <cfif hasWip><em>WIP <span data-wip-count>#column.cards.len()#</span> / #wipValue#</em></cfif>
                            </span>
                            <button class="lane-collapse-button" type="button" data-lane-collapse aria-label="#encodeForHTMLAttribute( column.is_collapsed ? $r( 'app.lane.expand' ) : $r( 'app.lane.collapse' ) )#" title="#encodeForHTMLAttribute( column.is_collapsed ? $r( 'app.lane.expand' ) : $r( 'app.lane.collapse' ) )#" data-collapse-label="#encodeForHTMLAttribute( $r( 'app.lane.collapse' ) )#" data-expand-label="#encodeForHTMLAttribute( $r( 'app.lane.expand' ) )#">
                                <svg class="icon lane-collapse-icon" aria-hidden="true"><use href="/resources/icons.svg###column.is_collapsed ? 'expand-horizontal' : 'collapse-horizontal'#"></use></svg>
                            </button>
                        </header>
                        <cfif hasWip><div class="lane-wip-progress#wipState#" data-wip-limit="#wipValue#" data-wip-value-template="#encodeForHTMLAttribute( $r( 'app.lane.wipValue' ) )#"><span role="progressbar" aria-label="#encodeForHTMLAttribute( $r( 'app.lane.wipProgress' ) )#" aria-valuemin="0" aria-valuemax="#wipValue#" aria-valuenow="#min( column.cards.len(), val( wipValue ) )#" aria-valuetext="#encodeForHTMLAttribute( wipAriaText )#" data-wip-progress><i style="width:#wipPercent#%"></i></span></div></cfif>
                        <div class="live-card-list" data-card-list>
                            <cfloop array="#column.cards#" item="card">
								<cfset cardCompleted=card.is_completed ?: false>
                                <article class="demo-card live-card priority-border-#encodeForHTMLAttribute( card.priority )##cardCompleted ? ' is-completed' : ''##card.is_blocked ? ' is-blocked' : ''#" draggable="#prc.workspaceBoard.board.role != 'viewer'#" data-card-id="#encodeForHTMLAttribute( card.id )#" data-card-title="#encodeForHTMLAttribute( card.title )#" data-card-completed="#cardCompleted ? 'true' : 'false'#">
                                    <div class="live-card-tags">
                                        <cfif len( card.labels_csv ?: "" )><cfloop list="#card.labels_csv#" item="label"><cfset labelColorIndex=( inputBaseN( left( hash( lCase( trim( label ) ), "MD5" ), 2 ), 16 ) mod 3 ) + 1><span class="card-label #listGetAt( 'label-violet,label-green,label-blue', labelColorIndex )#">#encodeForHTML( label )#</span></cfloop></cfif>
                                        <cfif card.is_blocked><span class="blocked"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg>#$r( "card.blocked" )#</span></cfif>
                                    </div>
                                    <span class="live-card-complete" aria-hidden="true"><svg class="icon"><use href="/resources/icons.svg##check"></use></svg></span>
                                    <span class="sr-only" data-card-completed-label #cardCompleted ? "" : "hidden"#>#$r( "card.completed" )#</span>
                                    <h3><a href="/app/cards/#encodeForURL(card.id)#" hx-get="/app/cards/#encodeForURL(card.id)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true">#encodeForHTML( card.title )#</a></h3>
                                    <cfif len( trim( card.description ?: "" ) )><p>#encodeForHTML( card.description )#</p></cfif>
                                    <div class="card-meta">
                                        <span class="card-meta-items">
                                            <cfif !isNull( card.due_at )><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg> #encodeForHTML( dateFormat( card.due_at, getFWLocale() == "pt_BR" ? "dd/MM" : "mmm d" ) )#</span></cfif>
                                            <cfif val( card.attachment_count ?: 0 )>
                                                <span class="card-attachment-indicator" tabindex="0" aria-describedby="card-attachments-#encodeForHTMLAttribute( card.id )#" data-card-attachments><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##paperclip"></use></svg><span class="card-attachment-tooltip" id="card-attachments-#encodeForHTMLAttribute( card.id )#" role="tooltip"><strong>#$r( "app.card.attachments" )#</strong><cfloop list="#card.attachment_names#" delimiters="#chr( 10 )#" item="attachmentName"><span>#encodeForHTML( attachmentName )#</span></cfloop></span></span>
                                            </cfif>
                                        </span>
                                        <cfif card.assignees.len()>
                                            <cfset assigneeNames=[]><cfloop array="#card.assignees#" item="cardAssignee"><cfset assigneeNames.append( cardAssignee.display_name )></cfloop>
                                            <span class="card-assignee-stack" tabindex="0" aria-label="#encodeForHTMLAttribute( arrayToList( assigneeNames, ', ' ) )#">
                                                <cfloop from="1" to="#min( 3, card.assignees.len() )#" index="assigneeIndex"><cfset cardAssignee=card.assignees[ assigneeIndex ]><i class="user-avatar account-avatar"><span>#encodeForHTML( cardAssignee.initials )#</span><cfif len( cardAssignee.avatar_id ?: "" )><img src="/app/users/#encodeForURL( cardAssignee.user_id )#/avatar?v=#encodeForURL( cardAssignee.avatar_id )#" alt=""></cfif></i></cfloop>
                                                <cfif card.assignees.len() gt 3><b>+#card.assignees.len() - 3#</b></cfif><span class="card-assignee-tooltip" role="tooltip"><strong>#$r( "card.assignees" )#</strong><cfloop array="#card.assignees#" item="cardAssignee"><span>#encodeForHTML( cardAssignee.display_name )#</span></cfloop></span>
                                            </span>
                                        </cfif>
                                    </div>
                                </article>
                            </cfloop>
                            <p class="column-empty" data-column-empty #column.cards.len() ? "hidden" : ""#>#$r( "app.column.empty" )#</p>
                        </div>
                        <cfif prc.workspaceBoard.board.role != "viewer"><cfset laneCardFormId="lane-card-form-" & column.id><footer class="lane-card-create" data-lane-card-create><button type="button" data-lane-card-toggle aria-expanded="false" aria-controls="#encodeForHTMLAttribute( laneCardFormId )#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg>#$r( "app.card.addInLane" )#</button><form id="#encodeForHTMLAttribute( laneCardFormId )#" method="post" action="/app/cards" hx-post="/app/cards" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" data-lane-card-form hidden><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.cardCsrfToken )#"><input type="hidden" name="columnId" value="#encodeForHTMLAttribute( column.id )#"><label class="sr-only" for="lane-card-title-#encodeForHTMLAttribute( column.id )#">#$r( "app.card.title" )#</label><input id="lane-card-title-#encodeForHTMLAttribute( column.id )#" name="title" required maxlength="255" placeholder="#encodeForHTMLAttribute( $r( 'app.card.titlePlaceholder' ) )#"><div><button type="submit" title="#encodeForHTMLAttribute( $r( 'app.card.create' ) )#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg><span class="sr-only">#$r( "app.card.create" )#</span></button><button type="button" data-lane-card-cancel title="#encodeForHTMLAttribute( $r( 'app.card.cancel' ) )#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##close"></use></svg><span class="sr-only">#$r( "app.card.cancel" )#</span></button></div></form></footer></cfif>
                        <div class="lane-resize-handle" role="separator" aria-orientation="vertical" aria-label="#encodeForHTMLAttribute( $r( 'app.lane.resize' ) )#" title="#encodeForHTMLAttribute( $r( 'app.lane.resize' ) )#" tabindex="0" data-lane-resize></div>
                    </article>
                </cfloop>
            </div>
            <div class="board-toast" role="status" aria-live="polite" data-board-toast></div>
        </cfif>
    </section>
</cfoutput>
