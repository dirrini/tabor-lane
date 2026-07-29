<cfoutput>
<main class="workspace-shell"<cfif prc.checkoutNotice == "success" && prc.billing.plan != "premium"> data-billing-pending data-billing-status-url="/app/billing/status"</cfif>>
    <button class="workspace-menu-toggle" type="button" data-workspace-menu-toggle aria-label="#$r( 'app.menu.open' )#" aria-expanded="false"><svg class="icon"><use href="/resources/icons.svg##menu"></use></svg></button>
    <aside class="workspace-sidebar">
        <button class="workspace-menu-close" type="button" data-workspace-menu-close aria-label="#$r( 'app.menu.close' )#"><svg class="icon"><use href="/resources/icons.svg##close"></use></svg></button>
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
        <form method="post" action="/auth/logout"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.logoutCsrfToken )#"><button class="workspace-back" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "app.logout" )#</button></form>
    </aside>
    <button class="workspace-menu-backdrop" type="button" data-workspace-menu-close aria-label="#$r( 'app.menu.close' )#"></button>

    <section class="workspace-main billing-main">
        <header class="workspace-header">
            <div><small>#encodeForHTML( prc.auth.workspaceName )#</small><h1>#$r( "billing.title" )#</h1></div>
        </header>

        <cfif prc.checkoutNotice == "success"><div class="form-success">#$r( "billing.checkout.success" )#</div></cfif>
        <cfif prc.checkoutNotice == "cancelled"><div class="billing-notice">#$r( "billing.checkout.cancelled" )#</div></cfif>
        <cfif prc.error.len()><div class="form-errors"><svg class="icon"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "billing.error" )#</p></div></cfif>

        <section class="billing-summary">
            <div class="billing-plan-icon"><svg class="icon" aria-hidden="true"><cfif prc.billing.plan == "premium"><use href="/resources/icons.svg##crown"></use><cfelse><use href="/resources/icons.svg##board"></use></cfif></svg></div>
            <div>
                <small>#$r( "billing.currentPlan" )#</small>
                <h2>#prc.billing.plan == "premium" ? $r( "pricing.premium.name" ) : $r( "pricing.free.name" )#</h2>
                <p>#$r( prc.billing.plan == "premium" ? "billing.premium.body" : "billing.free.body" )#</p>
            </div>
            <span class="plan-status plan-#encodeForHTMLAttribute( prc.billing.plan )#">#encodeForHTML( uCase( prc.billing.plan ) )#</span>
        </section>

        <cfif prc.billing.plan == "premium">
            <section class="members-panel billing-details">
                <div class="panel-heading"><div><h2>#$r( "billing.subscription.title" )#</h2><p>#$r( "billing.subscription.body" )#</p></div></div>
                <dl>
                    <div><dt>#$r( "billing.status" )#</dt><dd>#encodeForHTML( prc.billing.status )#</dd></div>
                    <div><dt>#$r( "billing.interval" )#</dt><dd>#encodeForHTML( prc.billing.interval )#</dd></div>
                    <cfif isDate( prc.billing.currentPeriodEnd )><div><dt>#$r( "billing.renews" )#</dt><dd>#dateFormat( prc.billing.currentPeriodEnd, "medium" )#</dd></div></cfif>
                </dl>
                <cfif prc.billing.canManage>
                    <form method="post" action="/app/billing/portal">
                        <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#">
                        <button class="button button-ghost" type="submit"><svg class="icon"><use href="/resources/icons.svg##external"></use></svg> #$r( "billing.portal" )#</button>
                    </form>
                </cfif>
            </section>
        <cfelse>
            <section class="billing-upgrade">
                <div>
                    <p class="eyebrow"><span></span>#$r( "pricing.premium.name" )#</p>
                    <h2>#$r( "billing.upgrade.title" )#</h2>
                    <p>#$r( "billing.upgrade.body" )#</p>
                    <ul>
                        <li>#$r( "pricing.premium.f1" )#</li>
                        <li>#$r( "pricing.premium.f2" )#</li>
                        <li>#$r( "pricing.premium.f3" )#</li>
                    </ul>
                </div>
                <cfif prc.billing.canManage && prc.billing.configured>
                    <div class="billing-options">
                        <form method="post" action="/app/billing/checkout">
                            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#">
                            <input type="hidden" name="interval" value="monthly">
                            <button class="billing-option" type="submit"><span><strong>#$r( "billing.monthly.title" )#</strong><small>#$r( "billing.monthly.body" )#</small></span><svg class="icon"><use href="/resources/icons.svg##arrow-right"></use></svg></button>
                        </form>
                        <form method="post" action="/app/billing/checkout">
                            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#">
                            <input type="hidden" name="interval" value="yearly">
                            <button class="billing-option recommended" type="submit"><span><strong>#$r( "billing.yearly.title" )#</strong><small>#$r( "billing.yearly.body" )#</small></span><svg class="icon"><use href="/resources/icons.svg##arrow-right"></use></svg></button>
                        </form>
                    </div>
                <cfelseif !prc.billing.canManage>
                    <div class="billing-notice">#$r( "billing.ownerOnly" )#</div>
                <cfelse>
                    <div class="billing-notice">#$r( "billing.notConfigured" )#</div>
                </cfif>
            </section>
        </cfif>
    </section>
</main>
</cfoutput>
