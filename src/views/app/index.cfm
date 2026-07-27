<cfoutput>
<main class="workspace-shell">
    <aside class="workspace-sidebar">
        <a class="brand" href="/">
            <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
            <span class="brand-name">Tabor<span>Lane</span></span>
        </a>
        <div class="workspace-picker"><span class="workspace-avatar">T</span><div><small>#$r( "app.workspace" )#</small><strong>Tabor Lane</strong></div><b><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chevron-down"></use></svg></b></div>
        <nav>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##home"></use></svg></span>#$r( "app.myWork" )#</a>
            <a href="##" class="active"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg></span>#$r( "app.boards" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg></span>#$r( "app.analytics" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg></span>#$r( "app.automations" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##settings"></use></svg></span>#$r( "app.settings" )#</a>
        </nav>
        <a class="workspace-back" href="/"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "app.back" )#</a>
    </aside>
    <section class="workspace-main">
        <header class="workspace-header">
            <div><small>#$r( "app.preview" )#</small><h1>#$r( "board.title" )#</h1></div>
            <div><span class="avatar avatar-a">MA</span><span class="avatar avatar-b">JL</span><button class="button button-primary button-small"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "app.newCard" )#</button></div>
        </header>
        <div class="preview-notice"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##info"></use></svg></span><p><strong>#$r( "app.preview" )#</strong> #$r( "app.previewBody" )#</p></div>
        <div class="workspace-board kanban-grid">
            <article class="kanban-column"><header><span class="column-dot dot-sand"></span><strong>#$r( "board.col1" )#</strong><b>2</b></header><div class="demo-card"><span class="card-label label-violet">#$r( "board.design" )#</span><h3>#$r( "board.card1" )#</h3><div class="card-meta"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##list-checks"></use></svg> 3/5</span><i class="avatar avatar-a">MA</i></div></div><div class="demo-card"><span class="card-label label-green">#$r( "board.marketing" )#</span><h3>#$r( "board.card2" )#</h3></div></article>
            <article class="kanban-column"><header><span class="column-dot dot-blue"></span><strong>#$r( "board.col2" )#</strong><em>#$r( "board.wip" )#</em></header><div class="demo-card"><span class="card-label label-blue">#$r( "board.ops" )#</span><h3>#$r( "board.card3" )#</h3><p>API · Webhooks · Forms</p></div><div class="demo-card"><div class="blocked"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg> #$r( "board.blocked" )#</div><h3>#$r( "board.card4" )#</h3></div></article>
            <article class="kanban-column"><header><span class="column-dot dot-amber"></span><strong>#$r( "board.col3" )#</strong><b>1</b></header><div class="demo-card"><span class="card-label label-green">#$r( "board.marketing" )#</span><h3>#$r( "board.card5" )#</h3></div></article>
            <article class="kanban-column"><header><span class="column-dot dot-green"></span><strong>#$r( "board.col4" )#</strong><b>1</b></header><div class="demo-card done-card"><span class="complete-check"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg></span><div><h3>#$r( "board.card6" )#</h3></div></div></article>
        </div>
    </section>
</main>
</cfoutput>
