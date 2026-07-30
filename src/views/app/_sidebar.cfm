<cfoutput>
<aside class="workspace-sidebar">
    <button class="workspace-menu-close" type="button" data-workspace-menu-close aria-label="#$r( 'app.menu.close' )#"><svg class="icon"><use href="/resources/icons.svg##close"></use></svg></button>
    <a class="brand" href="/"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span><span class="brand-name">Tabor<span>Lane</span></span></a>
    <div class="workspace-picker">
        <span class="workspace-avatar">#encodeForHTML( left( prc.auth.workspaceName, 1 ) )#</span>
        <div><small>#$r( "app.workspace" )#</small><strong>#encodeForHTML( prc.auth.workspaceName )#</strong></div>
        <b><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chevron-down"></use></svg></b>
    </div>
    <nav hx-boost="true" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true">
        <a href="/app/my-work" class="#prc.page == 'myWork' ? 'active' : ''#" #prc.page == 'myWork' ? 'aria-current="page"' : ''#><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##home"></use></svg></span>#$r( "app.myWork" )#</a>
        <a href="/app" class="#prc.page == 'app' ? 'active' : ''#" #prc.page == 'app' ? 'aria-current="page"' : ''#><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg></span>#$r( "app.boards" )#</a>
        <a href="/app/members" class="#prc.page == 'members' ? 'active' : ''#" #prc.page == 'members' ? 'aria-current="page"' : ''#><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg></span>#$r( "members.nav" )#</a>
        <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg></span>#$r( "app.analytics" )#</a>
        <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg></span>#$r( "app.automations" )#</a>
        <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##settings"></use></svg></span>#$r( "app.settings" )#</a>
    </nav>
    <a class="workspace-account #prc.page == 'profile' || prc.page == 'billing' ? 'active' : ''#" href="/app/profile" hx-get="/app/profile" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true" #prc.page == 'profile' || prc.page == 'billing' ? 'aria-current="page"' : ''#>
        <span class="workspace-avatar account-avatar">#encodeForHTML( left( prc.auth.displayName, 1 ) )#</span>
        <div><strong>#encodeForHTML( prc.auth.displayName )#</strong><small>#encodeForHTML( $r( "workspace.role.#prc.auth.role#", prc.auth.role ) )# &middot; #encodeForHTML( prc.auth.email )#</small></div>
    </a>
    <form method="post" action="/auth/logout"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.logoutCsrfToken )#"><button class="workspace-back" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "app.logout" )#</button></form>
</aside>
</cfoutput>
