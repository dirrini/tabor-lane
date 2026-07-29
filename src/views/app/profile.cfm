<cfoutput>
<main class="workspace-shell"<cfif prc.checkoutNotice == "success" && prc.billing.plan != "premium"> data-billing-pending data-billing-status-url="/app/billing/status" data-billing-refresh-url="/app/profile"</cfif>>
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
        <cfif prc.checkoutNotice == "success"><div class="form-success">#$r( "billing.checkout.success" )#</div></cfif>
        <cfif prc.checkoutNotice == "cancelled"><div class="billing-notice">#$r( "billing.checkout.cancelled" )#</div></cfif>
        <cfif prc.error.len()><div class="form-errors"><svg class="icon"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "profile.error.#prc.error#", $r( "profile.error.generic" ) )#</p></div></cfif>

        <div class="profile-overview">
            <section class="profile-plan-card #prc.billing.plan == 'premium' ? 'premium' : ''#">
                <div class="profile-plan-icon"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##building"></use></svg></div>
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
            </section>

            <section class="profile-subscription-card">
                <div class="profile-subscription-heading">
                    <div><small>#$r( "profile.subscription.eyebrow" )#</small><h2>#$r( prc.billing.plan == "premium" ? "profile.subscription.manage" : "billing.upgrade.title" )#</h2></div>
                    <cfif prc.billing.plan == "premium"><svg class="icon profile-crown"><use href="/resources/icons.svg##crown"></use></svg></cfif>
                </div>
                <cfif prc.billing.plan == "premium">
                    <p class="profile-subscription-copy">#$r( "billing.premium.body" )#</p>
                    <cfif prc.billing.canManage><form method="post" action="/app/billing/portal"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#"><button class="button button-dark" type="submit"><svg class="icon"><use href="/resources/icons.svg##external"></use></svg> #$r( "billing.portal" )#</button></form></cfif>
                <cfelseif prc.billing.canManage && prc.billing.configured>
                    <div class="profile-billing-options">
                        <form method="post" action="/app/billing/checkout"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#"><input type="hidden" name="interval" value="monthly"><button class="billing-option" type="submit"><span><strong>#$r( "billing.monthly.title" )#</strong><small>#$r( "billing.monthly.body" )#</small></span><svg class="icon"><use href="/resources/icons.svg##arrow-right"></use></svg></button></form>
                        <form method="post" action="/app/billing/checkout"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#"><input type="hidden" name="interval" value="yearly"><button class="billing-option recommended" type="submit"><span><strong>#$r( "billing.yearly.title" )#</strong><small>#$r( "billing.yearly.body" )#</small></span><svg class="icon"><use href="/resources/icons.svg##arrow-right"></use></svg></button></form>
                    </div>
                <cfelseif !prc.billing.canManage>
                    <div class="billing-notice">#$r( "billing.ownerOnly" )#</div>
                <cfelse>
                    <div class="billing-notice">#$r( "billing.notConfigured" )#</div>
                </cfif>
                <p class="stripe-safety"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##shield-check"></use></svg><span>#$r( "profile.subscription.stripe" )#</span></p>
            </section>
        </div>

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
