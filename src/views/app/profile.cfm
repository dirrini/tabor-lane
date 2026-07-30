<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
    <section id="workspace-main" class="workspace-main profile-main" data-workspace-page="profile"<cfif prc.checkoutNotice == "success" && prc.billing.plan != "premium"> data-billing-pending data-billing-status-url="/app/billing/status" data-billing-refresh-url="/app/profile"</cfif>>
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
                        <p>#$r( "profile.validUntil" )#: <b>#isDate( prc.billing.currentPeriodEnd ) ? lsDateFormat( prc.billing.currentPeriodEnd, "long", prc.auth.locale ?: "en_US" ) : $r( "profile.pendingDate" )#</b></p>
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
                    <cfif prc.billing.canManage><form method="post" action="/app/billing/portal"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingPortalCsrfToken )#"><button class="button button-dark" type="submit"><svg class="icon"><use href="/resources/icons.svg##external"></use></svg> #$r( "billing.portal" )#</button></form></cfif>
                <cfelseif prc.billing.canManage && prc.billing.configured>
                    <div class="profile-billing-options">
                        <form method="post" action="/app/billing/checkout"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#"><input type="hidden" name="interval" value="monthly"><button class="billing-option" type="submit"><div class="billing-option-copy"><strong>#$r( "billing.monthly.title" )#</strong><cfif prc.pricing.monthly.display.len()><b>#encodeForHTML( prc.pricing.monthly.display )# <small>#$r( "billing.perMonth" )#</small></b></cfif><small>#$r( "billing.monthly.body" )#</small></div><svg class="icon"><use href="/resources/icons.svg##arrow-right"></use></svg></button></form>
                        <form method="post" action="/app/billing/checkout"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.billingCsrfToken )#"><input type="hidden" name="interval" value="yearly"><button class="billing-option" type="submit"><div class="billing-option-copy"><div class="billing-option-title"><strong>#$r( "billing.yearly.title" )#</strong><span class="best-value-chip"><svg class="icon"><use href="/resources/icons.svg##star"></use></svg>#$r( "billing.recommended" )#</span></div><cfif prc.pricing.yearly.display.len()><b>#encodeForHTML( prc.pricing.yearly.display )# <small>#$r( "billing.perYear" )#</small></b></cfif><small>#$r( "billing.yearly.body" )#</small></div><svg class="icon"><use href="/resources/icons.svg##arrow-right"></use></svg></button></form>
                    </div>
                <cfelseif !prc.billing.canManage>
                    <div class="billing-notice">#$r( "billing.ownerOnly" )#</div>
                <cfelse>
                    <div class="billing-notice">#$r( "billing.notConfigured" )#</div>
                </cfif>
                <p class="stripe-safety"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##shield-check"></use></svg><span>#$r( "profile.subscription.stripe" )#</span></p>
            </section>
        </div>

        <section id="profile-avatar" class="members-panel profile-panel profile-avatar-panel"
            data-avatar-manager
            data-avatar-presign-url="/app/profile/avatar/presign"
            data-avatar-complete-url-template="/app/profile/avatar/{id}/complete"
            data-avatar-remove-url="/app/profile/avatar/remove"
            data-avatar-csrf-token="#encodeForHTMLAttribute( prc.avatarCsrfToken )#"
            data-avatar-max-source-bytes="5242880"
            data-avatar-invalid-type="#encodeForHTMLAttribute( $r( 'profile.avatar.error.invalid_type' ) )#"
            data-avatar-source-too-large="#encodeForHTMLAttribute( $r( 'profile.avatar.error.source_too_large' ) )#"
            data-avatar-source-dimensions="#encodeForHTMLAttribute( $r( 'profile.avatar.error.source_dimensions' ) )#"
            data-avatar-output-too-large="#encodeForHTMLAttribute( $r( 'profile.avatar.error.output_too_large' ) )#"
            data-avatar-invalid-output="#encodeForHTMLAttribute( $r( 'profile.avatar.error.invalid_output' ) )#"
            data-avatar-invalid-dimensions="#encodeForHTMLAttribute( $r( 'profile.avatar.error.invalid_dimensions' ) )#"
            data-avatar-rate="#encodeForHTMLAttribute( $r( 'profile.avatar.error.rate' ) )#"
            data-avatar-generic-error="#encodeForHTMLAttribute( $r( 'profile.avatar.error.generic' ) )#"
            data-avatar-uploading="#encodeForHTMLAttribute( $r( 'profile.avatar.uploading' ) )#"
            data-avatar-saved="#encodeForHTMLAttribute( $r( 'profile.avatar.saved' ) )#"
            data-avatar-removed="#encodeForHTMLAttribute( $r( 'profile.avatar.removed' ) )#"
            data-avatar-remove-confirm="#encodeForHTMLAttribute( $r( 'profile.avatar.removeConfirm' ) )#">
            <div class="panel-heading"><div><h2>#$r( "profile.avatar.title" )#</h2><p>#$r( "profile.avatar.body" )#</p></div></div>
            <div class="profile-avatar-manager">
                <div class="profile-avatar-preview user-avatar account-avatar" data-avatar-preview>
                    <span data-avatar-initials>#encodeForHTML( prc.avatarInitials )#</span>
                    <cfif prc.avatar.available><img src="#encodeForHTMLAttribute( prc.avatar.url )#" alt=""></cfif>
                </div>
                <div class="profile-avatar-actions">
                    <p>#$r( "profile.avatar.hint" )#</p>
                    <label class="button button-primary button-small profile-avatar-file">
                        <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##upload"></use></svg>
                        <span>#$r( prc.avatar.available ? "profile.avatar.replace" : "profile.avatar.choose" )#</span>
                        <input class="sr-only" type="file" accept="image/jpeg,image/png,image/webp" data-avatar-file>
                    </label>
                    <cfif prc.avatar.available><button class="button button-ghost button-small" type="button" data-avatar-remove><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##trash"></use></svg>#$r( "profile.avatar.remove" )#</button></cfif>
                </div>
                <div class="avatar-crop-editor" data-avatar-editor hidden>
                    <div class="avatar-crop-stage" data-avatar-stage tabindex="0" role="application" aria-label="#encodeForHTMLAttribute( $r( 'profile.avatar.cropArea' ) )#">
                        <img data-avatar-crop-image alt="">
                        <span aria-hidden="true"></span>
                    </div>
                    <div class="avatar-crop-controls">
                        <label>#$r( "profile.avatar.zoom" )#<input type="range" min="1" max="3" step="0.01" value="1" data-avatar-zoom></label>
                        <p>#$r( "profile.avatar.cropHint" )#</p>
                        <div>
                            <button class="button button-ghost button-small" type="button" data-avatar-cancel>#$r( "app.card.cancel" )#</button>
                            <button class="button button-primary button-small" type="button" data-avatar-save><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg>#$r( "profile.avatar.usePhoto" )#</button>
                        </div>
                    </div>
                </div>
                <p class="profile-avatar-status" role="status" aria-live="polite" data-avatar-status></p>
            </div>
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
                <div><dt>#$r( "profile.details.role" )#</dt><dd>#encodeForHTML( $r( "workspace.role.#prc.account.role#", prc.account.role ) )#</dd></div>
                <div><dt>#$r( "profile.details.memberSince" )#</dt><dd>#lsDateFormat( prc.account.member_since, "long", prc.auth.locale ?: "en_US" )#</dd></div>
                <div><dt>#$r( "profile.details.accountCreated" )#</dt><dd>#lsDateFormat( prc.account.created_at, "long", prc.auth.locale ?: "en_US" )#</dd></div>
            </dl>
        </section>
    </section>
</cfoutput>
