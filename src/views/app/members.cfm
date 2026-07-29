<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
    <section id="workspace-main" class="workspace-main members-main" data-workspace-page="members">
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
                            <span class="role-badge">#encodeForHTML( $r( "workspace.role.#member.role#", member.role ) )#</span>
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
                    <div class="pending-row"><span>#encodeForHTML( invitation.email )#</span><small>#encodeForHTML( $r( "workspace.role.#invitation.role#", invitation.role ) )#</small></div>
                </cfloop>
            </section>
        </cfif>
    </section>
</cfoutput>
