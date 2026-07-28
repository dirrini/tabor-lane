<cfoutput>
<main class="workspace-shell">
    <aside class="workspace-sidebar">
        <a class="brand" href="/"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span><span class="brand-name">Tabor<span>Lane</span></span></a>
        <div class="workspace-picker">
            <span class="workspace-avatar">#encodeForHTML( left( prc.auth.workspaceName, 1 ) )#</span>
            <div><small>#$r( "app.workspace" )#</small><strong>#encodeForHTML( prc.auth.workspaceName )#</strong></div>
        </div>
        <nav>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##home"></use></svg></span>#$r( "app.myWork" )#</a>
            <a href="/app"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##board"></use></svg></span>#$r( "app.boards" )#</a>
            <a href="/app/members" class="active"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg></span>#$r( "members.nav" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg></span>#$r( "app.analytics" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg></span>#$r( "app.automations" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##settings"></use></svg></span>#$r( "app.settings" )#</a>
        </nav>
        <a class="workspace-account" href="/app/profile">
            <span class="workspace-avatar account-avatar">#encodeForHTML( left( prc.auth.displayName, 1 ) )#</span>
            <div><strong>#encodeForHTML( prc.auth.displayName )#</strong><small>#encodeForHTML( prc.auth.role )# · #encodeForHTML( prc.auth.email )#</small></div>
        </a>
        <form method="post" action="/auth/logout"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.logoutCsrfToken )#"><button class="workspace-back" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "app.logout" )#</button></form>
    </aside>
    <section class="workspace-main members-main">
        <header class="workspace-header">
            <div><small>#encodeForHTML( prc.auth.workspaceName )#</small><h1>#$r( "members.title" )#</h1></div>
        </header>

        <cfif prc.notice.len()><div class="form-success">#$r( "members.invited" )#</div></cfif>
        <cfif prc.error.len()><div class="form-errors"><svg class="icon"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "members.error" )#</p></div></cfif>
        <cfif prc.developmentInvitationToken.len()>
            <a class="development-invite-link" href="/invite/#encodeForURL( prc.developmentInvitationToken )#">#$r( "members.development" )#</a>
        </cfif>

        <div class="members-layout">
            <section class="members-panel">
                <div class="panel-heading"><div><h2>#$r( "members.current" )#</h2><p>#$r( "members.currentBody" )#</p></div><span>#prc.members.len()#</span></div>
                <div class="member-list">
                    <cfloop array="#prc.members#" item="member">
                        <article class="member-row">
                            <span class="workspace-avatar account-avatar">#encodeForHTML( left( member.display_name, 1 ) )#</span>
                            <div><strong>#encodeForHTML( member.display_name )#</strong><small>#encodeForHTML( member.email )#</small></div>
                            <span class="role-badge">#encodeForHTML( member.role )#</span>
                        </article>
                    </cfloop>
                </div>
            </section>

            <cfif prc.canInvite>
                <section class="members-panel invite-panel">
                    <div class="panel-heading"><div><h2>#$r( "members.invite.title" )#</h2><p>#$r( "members.invite.body" )#</p></div></div>
                    <form class="auth-form" method="post" action="/app/members/invite">
                        <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.inviteCsrfToken )#">
                        <label>#$r( "auth.email" )#<input name="email" type="email" required placeholder="teammate@company.com"></label>
                        <label>#$r( "members.role" )#
                            <select name="role"><option value="member">#$r( "members.role.member" )#</option><option value="admin">#$r( "members.role.admin" )#</option><option value="viewer">#$r( "members.role.viewer" )#</option></select>
                        </label>
                        <button class="button button-primary" type="submit"><svg class="icon"><use href="/resources/icons.svg##mail"></use></svg> #$r( "members.invite.submit" )#</button>
                    </form>
                </section>
            </cfif>
        </div>

        <cfif prc.invitations.len()>
            <section class="members-panel pending-panel">
                <div class="panel-heading"><div><h2>#$r( "members.pending" )#</h2></div><span>#prc.invitations.len()#</span></div>
                <cfloop array="#prc.invitations#" item="invitation">
                    <div class="pending-row"><span>#encodeForHTML( invitation.email )#</span><small>#encodeForHTML( invitation.role )#</small></div>
                </cfloop>
            </section>
        </cfif>
    </section>
</main>
</cfoutput>
