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
            <a href="/app/members"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg></span>#$r( "members.nav" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##chart"></use></svg></span>#$r( "app.analytics" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg></span>#$r( "app.automations" )#</a>
            <a href="##"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##settings"></use></svg></span>#$r( "app.settings" )#</a>
        </nav>
        <a class="workspace-account active" href="/app/profile">
            <span class="workspace-avatar account-avatar">#encodeForHTML( left( prc.auth.displayName, 1 ) )#</span>
            <div><strong>#encodeForHTML( prc.auth.displayName )#</strong><small>#encodeForHTML( prc.auth.role )# &middot; #encodeForHTML( prc.auth.email )#</small></div>
        </a>
        <form method="post" action="/auth/logout"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.logoutCsrfToken )#"><button class="workspace-back" type="submit"><svg class="icon"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "app.logout" )#</button></form>
    </aside>

    <section class="workspace-main profile-main">
        <header class="workspace-header">
            <div><small>#$r( "profile.account" )#</small><h1>#$r( "profile.title" )#</h1></div>
        </header>

        <cfif prc.notice.len()><div class="form-success">#$r( prc.notice == "1" && structKeyExists( rc, "passwordChanged" ) ? "profile.password.success" : "profile.saved" )#</div></cfif>
        <cfif prc.error.len()><div class="form-errors"><svg class="icon"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "profile.error.#prc.error#", $r( "profile.error.generic" ) )#</p></div></cfif>

        <section class="profile-plan-card #prc.billing.plan == 'premium' ? 'premium' : ''#">
            <div class="profile-plan-icon"><svg class="icon"><cfif prc.billing.plan == "premium"><use href="/resources/icons.svg##crown"></use><cfelse><use href="/resources/icons.svg##board"></use></cfif></svg></div>
            <div>
                <small>#$r( "profile.workspacePlan" )#</small>
                <h2>#encodeForHTML( prc.account.workspace_name )#</h2>
                <strong>#prc.billing.plan == "premium" ? $r( "pricing.premium.name" ) : $r( "pricing.free.name" )#</strong>
                <cfif prc.billing.plan == "premium">
                    <p>#$r( "profile.validUntil" )#: <b>#isDate( prc.billing.currentPeriodEnd ) ? dateFormat( prc.billing.currentPeriodEnd, "medium" ) : $r( "profile.pendingDate" )#</b></p>
                <cfelse>
                    <p>#$r( "billing.free.body" )#</p>
                </cfif>
            </div>
            <a class="button #prc.billing.plan == 'premium' ? 'button-dark' : 'button-primary'#" href="/app/billing">#prc.billing.plan == "premium" ? $r( "billing.portal" ) : $r( "profile.upgrade" )#</a>
        </section>

        <div class="profile-grid">
            <section class="members-panel profile-panel">
                <div class="panel-heading"><div><h2>#$r( "profile.personal.title" )#</h2><p>#$r( "profile.personal.body" )#</p></div></div>
                <form class="auth-form" method="post" action="/app/profile/details">
                    <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.profileCsrfToken )#">
                    <label>#$r( "auth.name" )#<input name="displayName" value="#encodeForHTMLAttribute( prc.account.display_name )#" maxlength="160" required></label>
                    <label>#$r( "auth.email" )#<input name="email" type="email" value="#encodeForHTMLAttribute( prc.account.email )#" maxlength="320" required><small>#$r( "profile.emailHint" )#</small></label>
                    <label>#$r( "profile.language" )#<select name="locale"><option value="en_US" #prc.account.locale == "en_US" ? "selected" : ""#>English</option><option value="pt_BR" #prc.account.locale == "pt_BR" ? "selected" : ""#>Português (Brasil)</option></select></label>
                    <button class="button button-primary" type="submit">#$r( "profile.save" )#</button>
                </form>
            </section>

            <section class="members-panel profile-panel">
                <div class="panel-heading"><div><h2>#$r( "profile.password.title" )#</h2><p>#$r( prc.account.has_password ? "profile.password.body" : "profile.password.createBody" )#</p></div></div>
                <form class="auth-form" method="post" action="/app/profile/password">
                    <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.passwordCsrfToken )#">
                    <cfif prc.account.has_password><label>#$r( "profile.password.current" )#<input name="currentPassword" type="password" autocomplete="current-password" required></label></cfif>
                    <label>#$r( "profile.password.new" )#<input name="newPassword" type="password" autocomplete="new-password" minlength="10" required></label>
                    <label>#$r( "profile.password.confirm" )#<input name="confirmPassword" type="password" autocomplete="new-password" minlength="10" required></label>
                    <button class="button button-dark" type="submit">#$r( "profile.password.submit" )#</button>
                </form>
            </section>
        </div>

        <section class="members-panel profile-panel account-details">
            <div class="panel-heading"><div><h2>#$r( "profile.details.title" )#</h2><p>#$r( "profile.details.body" )#</p></div></div>
            <dl>
                <div><dt>#$r( "profile.details.accountId" )#</dt><dd>#encodeForHTML( prc.account.id )#</dd></div>
                <div><dt>#$r( "profile.details.workspaceId" )#</dt><dd>#encodeForHTML( prc.account.workspace_id )#</dd></div>
                <div><dt>#$r( "profile.details.slug" )#</dt><dd>#encodeForHTML( prc.account.workspace_slug )#</dd></div>
                <div><dt>#$r( "profile.details.role" )#</dt><dd>#encodeForHTML( prc.account.role )#</dd></div>
                <div><dt>#$r( "profile.details.memberSince" )#</dt><dd>#dateFormat( prc.account.member_since, "medium" )#</dd></div>
                <div><dt>#$r( "profile.details.accountCreated" )#</dt><dd>#dateFormat( prc.account.created_at, "medium" )#</dd></div>
            </dl>
        </section>
    </section>
</main>
</cfoutput>
