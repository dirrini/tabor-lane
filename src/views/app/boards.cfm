<cfscript>
    management=prc.management;
    selected=management.selectedBoard;
    noticeKeys="created,saved,archived,restored,board_moved,lane_created,lane_saved,lane_deleted,lane_moved";
    errorKeys="expired,invalid,forbidden,board_limit,last_board,lane_limit,last_lane,lane_not_empty,invalid_wip,not_found";
    noticeKey=listFindNoCase(noticeKeys,prc.notice)?prc.notice:"";
    errorKey=listFindNoCase(errorKeys,prc.error)?prc.error:"generic";
    backUrl="/app";
    if(selected.count() && !selected.is_archived) backUrl &= "?boardId=" & encodeForURL(selected.id);
    selectedActiveIndex=0;
    for(i=1;i<=management.activeBoards.len();i++)
        if(selected.count() && management.activeBoards[i].id==selected.id) selectedActiveIndex=i;
    moveLeftDisabled=selectedActiveIndex<=1 ? "disabled" : "";
    moveRightDisabled=selectedActiveIndex>=management.activeBoards.len() ? "disabled" : "";
</cfscript>
<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML(prc.pageTitle)#</title></cfif>
<section id="workspace-main" class="workspace-main board-management-main" data-workspace-page="app">
    <header class="workspace-header board-management-header">
        <div><small>#encodeForHTML(prc.auth.workspaceName)# · #encodeForHTML(uCase(management.plan))#</small><h1>#$r("boards.title")#</h1><p>#$r("boards.subtitle")#</p></div>
        <a class="button button-ghost button-small" href="#encodeForHTMLAttribute(backUrl)#" hx-get="#encodeForHTMLAttribute(backUrl)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r("boards.back")#</a>
    </header>

    <cfif noticeKey.len()><div class="form-success">#$r("boards.notice.#noticeKey#")#</div></cfif>
    <cfif prc.error.len()><div class="form-errors"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg><p>#$r("boards.error.#errorKey#")#</p></div></cfif>
    <cfif !management.canManage><div class="form-errors board-read-only"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg><p>#$r("boards.readOnly")#</p></div></cfif>

    <div class="board-management-layout">
        <aside class="board-catalog">
            <section class="management-panel">
                <div class="panel-heading"><div><h2>#$r("boards.active")#</h2><p>#$r("boards.activeBody")#</p></div><span>#management.activeBoards.len()#<cfif management.maxBoards> / #management.maxBoards#</cfif></span></div>
                <nav class="management-board-list" aria-label="#encodeForHTMLAttribute($r('boards.active'))#">
                    <cfloop array="#management.activeBoards#" item="board"><a class="#selected.count() && selected.id==board.id ? 'active' : ''#" href="/app/boards/manage?boardId=#encodeForURL(board.id)#" hx-get="/app/boards/manage?boardId=#encodeForURL(board.id)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg><span><strong>#encodeForHTML(board.name)#</strong><small>#board.active_card_count# #$r("boards.cards")#</small></span></a></cfloop>
                </nav>
            </section>

            <cfif management.archivedBoards.len()>
                <section class="management-panel archived-board-panel">
                    <div class="panel-heading"><div><h2>#$r("boards.archived")#</h2></div><span>#management.archivedBoards.len()#</span></div>
                    <nav class="management-board-list"><cfloop array="#management.archivedBoards#" item="board"><a class="#selected.count() && selected.id==board.id ? 'active' : ''#" href="/app/boards/manage?boardId=#encodeForURL(board.id)#" hx-get="/app/boards/manage?boardId=#encodeForURL(board.id)#" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##archive"></use></svg><span><strong>#encodeForHTML(board.name)#</strong><small>#$r("boards.archivedItem")#</small></span></a></cfloop></nav>
                </section>
            </cfif>

            <cfif management.canManage>
                <section class="management-panel create-board-panel">
                    <div class="panel-heading"><div><h2>#$r("boards.create")#</h2><p>#$r("boards.createBody")#</p></div></div>
                    <cfif management.canCreateBoard>
                        <form class="management-form" method="post" action="/app/boards" hx-post="/app/boards" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML">
                            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#">
                            <label>#$r("boards.name")#<input name="name" required maxlength="160" placeholder="#encodeForHTMLAttribute($r('boards.namePlaceholder'))#"></label>
                            <label>#$r("boards.description")#<textarea name="description" maxlength="2000" rows="2"></textarea></label>
                            <label>#$r("boards.template")#<select name="template"><option value="blank">#$r("boards.template.blank")#</option><option value="software">#$r("boards.template.software")#</option><option value="marketing">#$r("boards.template.marketing")#</option><option value="personal">#$r("boards.template.personal")#</option></select></label>
                            <button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r("boards.createAction")#</button>
                        </form>
                    <cfelse><div class="plan-limit-message"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##crown"></use></svg><p>#$r("boards.limitReached")#</p><a href="/app/profile" hx-get="/app/profile" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-push-url="true">#$r("boards.viewPremium")#</a></div></cfif>
                </section>
            </cfif>
        </aside>

        <main class="board-editor">
            <cfif selected.count()>
                <section class="management-panel board-settings-panel">
                    <div class="panel-heading"><div><h2>#encodeForHTML(selected.name)#</h2><p>#selected.is_archived ? $r("boards.archivedBody") : $r("boards.settingsBody")#</p></div><span class="status-chip #selected.is_archived ? 'archived' : 'active'#">#selected.is_archived ? $r("boards.status.archived") : $r("boards.status.active")#</span></div>
                    <cfif management.canManage>
                        <form class="management-form board-settings-form" method="post" action="/app/boards/#encodeForURL(selected.id)#/update" hx-post="/app/boards/#encodeForURL(selected.id)#/update" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML">
                            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#">
                            <label>#$r("boards.name")#<input name="name" value="#encodeForHTMLAttribute(selected.name)#" required maxlength="160"></label>
                            <label>#$r("boards.description")#<textarea name="description" maxlength="2000" rows="2">#encodeForHTML(selected.description ?: "")#</textarea></label>
                            <button class="button button-primary button-small" type="submit">#$r("boards.save")#</button>
                        </form>
                        <div class="board-state-actions">
                            <cfif selected.is_archived>
                                <form method="post" action="/app/boards/#encodeForURL(selected.id)#/restore" hx-post="/app/boards/#encodeForURL(selected.id)#/restore" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#"><button class="button button-ghost button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##restore"></use></svg> #$r("boards.restore")#</button></form>
                            <cfelse>
                                <form method="post" action="/app/boards/#encodeForURL(selected.id)#/move" hx-post="/app/boards/#encodeForURL(selected.id)#/move" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#"><input type="hidden" name="direction" value="left"><button class="button button-ghost button-small" type="submit" #moveLeftDisabled# title="#encodeForHTMLAttribute($r('boards.moveLeft'))#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg><span class="sr-only">#$r("boards.moveLeft")#</span></button></form>
                                <form method="post" action="/app/boards/#encodeForURL(selected.id)#/move" hx-post="/app/boards/#encodeForURL(selected.id)#/move" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#"><input type="hidden" name="direction" value="right"><button class="button button-ghost button-small" type="submit" #moveRightDisabled# title="#encodeForHTMLAttribute($r('boards.moveRight'))#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg><span class="sr-only">#$r("boards.moveRight")#</span></button></form>
                                <form method="post" action="/app/boards/#encodeForURL(selected.id)#/archive" hx-post="/app/boards/#encodeForURL(selected.id)#/archive" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-confirm="#encodeForHTMLAttribute($r('boards.archiveConfirm'))#"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#"><button class="button button-danger-soft button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##archive"></use></svg> #$r("boards.archive")#</button></form>
                            </cfif>
                        </div>
                    </cfif>
                </section>

                <section class="management-panel lane-management-panel">
                    <div class="panel-heading"><div><h2>#$r("lanes.title")#</h2><p>#$r("lanes.subtitle")#</p></div><span>#management.lanes.len()#</span></div>
                    <div class="lane-management-list">
                        <cfloop array="#management.lanes#" item="lane" index="laneIndex">
                            <article class="lane-management-row lane-color-#encodeForHTMLAttribute(lane.color)#" data-lane-id="#encodeForHTMLAttribute(lane.id)#" data-lane-name="#encodeForHTMLAttribute(lane.name)#">
                                <span class="lane-color-mark"></span>
                                <cfif management.canManage && !selected.is_archived>
                                    <form class="lane-edit-form" method="post" action="/app/boards/#encodeForURL(selected.id)#/lanes/#encodeForURL(lane.id)#/update" hx-post="/app/boards/#encodeForURL(selected.id)#/lanes/#encodeForURL(lane.id)#/update" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML">
                                        <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#">
                                        <label><span>#$r("lanes.name")#</span><input name="name" value="#encodeForHTMLAttribute(lane.name)#" required maxlength="120"></label>
                                        <label><span>#$r("lanes.color")#</span><select name="color"><cfloop list="red,blue,amber,green,purple,slate" item="color"><option value="#color#" #lane.color==color ? "selected" : ""#>#$r("lanes.color.#color#")#</option></cfloop></select></label>
                                        <label><span>#$r("lanes.wip")#</span><input name="wipLimit" type="number" min="1" max="999" value="#isNull(lane.wip_limit) ? '' : encodeForHTMLAttribute(lane.wip_limit)#" placeholder="∞"></label>
                                        <button class="button button-ghost button-small" type="submit">#$r("lanes.save")#</button>
                                    </form>
                                    <div class="lane-row-actions">
                                        <form method="post" action="/app/boards/#encodeForURL(selected.id)#/lanes/#encodeForURL(lane.id)#/move" hx-post="/app/boards/#encodeForURL(selected.id)#/lanes/#encodeForURL(lane.id)#/move" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#"><input type="hidden" name="direction" value="up"><button type="submit" title="#encodeForHTMLAttribute($r('lanes.moveUp'))#" #laneIndex==1 ? "disabled" : ""#><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-up"></use></svg></button></form>
                                        <form method="post" action="/app/boards/#encodeForURL(selected.id)#/lanes/#encodeForURL(lane.id)#/move" hx-post="/app/boards/#encodeForURL(selected.id)#/lanes/#encodeForURL(lane.id)#/move" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#"><input type="hidden" name="direction" value="down"><button type="submit" title="#encodeForHTMLAttribute($r('lanes.moveDown'))#" #laneIndex==management.lanes.len() ? "disabled" : ""#><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-down"></use></svg></button></form>
                                        <form method="post" action="/app/boards/#encodeForURL(selected.id)#/lanes/#encodeForURL(lane.id)#/delete" hx-post="/app/boards/#encodeForURL(selected.id)#/lanes/#encodeForURL(lane.id)#/delete" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML" hx-confirm="#encodeForHTMLAttribute($r('lanes.deleteConfirm'))#"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#"><button class="danger" type="submit" title="#encodeForHTMLAttribute($r('lanes.delete'))#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##trash"></use></svg></button></form>
                                    </div>
                                <cfelse>
                                    <div class="lane-readonly-details"><strong>#encodeForHTML(lane.name)#</strong><small>#lane.active_card_count# #$r("boards.cards")# · #isNull(lane.wip_limit) ? $r("lanes.noWip") : "WIP " & lane.wip_limit#</small></div>
                                </cfif>
                            </article>
                        </cfloop>
                    </div>
                    <cfif management.canManage && !selected.is_archived>
                        <form class="create-lane-form" method="post" action="/app/boards/#encodeForURL(selected.id)#/lanes" hx-post="/app/boards/#encodeForURL(selected.id)#/lanes" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML">
                            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute(prc.boardCsrfToken)#">
                            <label><span>#$r("lanes.newName")#</span><input name="name" required maxlength="120" placeholder="#encodeForHTMLAttribute($r('lanes.namePlaceholder'))#"></label>
                            <label><span>#$r("lanes.color")#</span><select name="color"><cfloop list="red,blue,amber,green,purple,slate" item="color"><option value="#color#">#$r("lanes.color.#color#")#</option></cfloop></select></label>
                            <label><span>#$r("lanes.wip")#</span><input name="wipLimit" type="number" min="1" max="999" placeholder="∞"></label>
                            <button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r("lanes.add")#</button>
                        </form>
                    </cfif>
                </section>
            <cfelse><div class="app-empty-state"><svg class="icon"><use href="/resources/icons.svg##board"></use></svg><h2>#$r("boards.empty")#</h2></div></cfif>
        </main>
    </div>
</section>
</cfoutput>
