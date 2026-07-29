<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
    <section id="workspace-main" class="workspace-main billing-main" data-workspace-page="billing"<cfif prc.checkoutNotice == "success" && prc.billing.plan != "premium"> data-billing-pending data-billing-status-url="/app/billing/status"</cfif>>
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
                    <cfif isDate( prc.billing.currentPeriodEnd )><div><dt>#$r( "billing.renews" )#</dt><dd>#lsDateFormat( prc.billing.currentPeriodEnd, "long", prc.auth.locale ?: "en_US" )#</dd></div></cfif>
                </dl>
                <cfif prc.billing.canManage>
                    <form method="post" action="/app/billing/portal">
                        <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingPortalCsrfToken )#">
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
                            <button class="billing-option" type="submit"><div class="billing-option-copy"><strong>#$r( "billing.monthly.title" )#</strong><cfif prc.pricing.monthly.display.len()><b>#encodeForHTML( prc.pricing.monthly.display )# <small>#$r( "billing.perMonth" )#</small></b></cfif><small>#$r( "billing.monthly.body" )#</small></div><svg class="icon"><use href="/resources/icons.svg##arrow-right"></use></svg></button>
                        </form>
                        <form method="post" action="/app/billing/checkout">
                            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#">
                            <input type="hidden" name="interval" value="yearly">
                            <button class="billing-option" type="submit"><div class="billing-option-copy"><div class="billing-option-title"><strong>#$r( "billing.yearly.title" )#</strong><span class="best-value-chip"><svg class="icon"><use href="/resources/icons.svg##star"></use></svg>#$r( "billing.recommended" )#</span></div><cfif prc.pricing.yearly.display.len()><b>#encodeForHTML( prc.pricing.yearly.display )# <small>#$r( "billing.perYear" )#</small></b></cfif><small>#$r( "billing.yearly.body" )#</small></div><svg class="icon"><use href="/resources/icons.svg##arrow-right"></use></svg></button>
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
</cfoutput>
