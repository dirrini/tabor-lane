<cfscript>
	management = prc.automationManagement;
	noticeKeys = "created,enabled,paused,removed";
	errorKeys = "expired,invalid,forbidden,plan_required,not_found,duplicate,rule_limit,generic";
	noticeKey = listFindNoCase( noticeKeys, prc.notice ?: "" ) ? prc.notice : "";
	errorKey = listFindNoCase( errorKeys, prc.error ?: "" ) ? prc.error : "";
	locale = getFWLocale();
	dateMask = locale == "pt_BR" ? "dd/MM/yyyy HH:mm" : "MMM d, yyyy h:nn tt";
</cfscript>
<cfoutput>
<section id="automation-panel" class="automation-panel-main" aria-live="polite">
	<cfif noticeKey.len()>
		<div class="form-success"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg><p>#$r( "automations.notice.#noticeKey#" )#</p></div>
	</cfif>
	<cfif errorKey.len()>
		<div class="form-errors"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "automations.error.#errorKey#" )#</p></div>
	</cfif>

	<cfif !management.isPremium>
		<section class="management-panel automation-premium-card">
			<div class="automation-premium-icon"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##crown"></use></svg></div>
			<div><span class="status-chip premium">#$r( "automations.premium.badge" )#</span><h2>#$r( "automations.premium.title" )#</h2><p>#$r( "automations.premium.body" )#</p></div>
			<a class="button button-primary button-small" href="/app/profile" hx-get="/app/profile" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true">#$r( "automations.premium.cta" )#</a>
		</section>
	</cfif>

	<cfif !management.canManage>
		<div class="form-errors automation-read-only"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg><p>#$r( "automations.readOnly" )#</p></div>
	</cfif>

	<div class="automation-management-layout#management.canManage && management.isPremium ? '' : ' is-single-column'#">
		<cfif management.canManage && management.isPremium>
			<aside class="management-panel automation-builder">
				<div class="panel-heading"><div><h2>#$r( "automations.create.title" )#</h2><p>#$r( "automations.create.body" )#</p></div><span>#management.rules.len()# / #management.maxRules#</span></div>
				<cfif management.canCreate>
					<form class="management-form" method="post" action="/app/automations"
						hx-post="/app/automations" hx-target="##automation-panel" hx-select="##automation-panel" hx-swap="outerHTML" hx-disabled-elt="find button">
						<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.automationCsrfToken )#">
						<label>#$r( "automations.field.name" )#<input name="name" required maxlength="160" placeholder="#encodeForHTMLAttribute( $r( 'automations.field.namePlaceholder' ) )#"></label>
						<div class="automation-step trigger">
							<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>#$r( "automations.when" )#</span>
							<label>#$r( "automations.field.destination" )#
								<select name="destination" required>
									<option value="">#$r( "automations.field.destinationPlaceholder" )#</option>
									<cfloop array="#management.destinations#" item="destination">
										<option value="#encodeForHTMLAttribute( destination.board_id & ':' & destination.column_id )#">#encodeForHTML( destination.board_name )# &mdash; #encodeForHTML( destination.column_name )##destination.is_hidden_from_members ? " · " & $r( "automations.hiddenLane" ) : ""#</option>
									</cfloop>
								</select>
							</label>
						</div>
						<div class="automation-step action">
							<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bell"></use></svg>#$r( "automations.then" )#</span>
							<label>#$r( "automations.field.recipient" )#
								<select name="recipientUserId" required>
									<option value="">#$r( "automations.field.recipientPlaceholder" )#</option>
									<cfloop array="#management.members#" item="member"><option value="#encodeForHTMLAttribute( member.id )#">#encodeForHTML( member.display_name )#</option></cfloop>
								</select>
							</label>
						</div>
						<button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg>#$r( "automations.create.action" )#</button>
					</form>
				<cfelse>
					<div class="plan-limit-message"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "automations.limitReached" )#</p></div>
				</cfif>
			</aside>
		</cfif>

		<section class="management-panel automation-catalog">
			<div class="panel-heading"><div><h2>#$r( "automations.list.title" )#</h2><p>#$r( "automations.list.body" )#</p></div><span>#management.rules.len()#</span></div>
			<cfif !management.rules.len()>
				<div class="automation-empty"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg><h3>#$r( "automations.empty.title" )#</h3><p>#$r( "automations.empty.body" )#</p></div>
		<cfelse>
				<div class="automation-rule-list">
					<cfloop array="#management.rules#" item="rule">
						<cfset ruleUnavailable = rule.board_is_archived || rule.column_is_archived>
						<cfset effectiveActive = rule.is_enabled && management.isPremium && !ruleUnavailable>
						<cfset statusKey = ruleUnavailable ? "unavailable" : ( effectiveActive ? "active" : "paused" )>
						<article class="automation-rule #effectiveActive ? 'is-active' : 'is-paused'#" data-automation-id="#encodeForHTMLAttribute( rule.id )#" data-automation-name="#encodeForHTMLAttribute( rule.name )#">
							<header><div><span class="automation-rule-icon"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg></span><div><h3>#encodeForHTML( rule.name )#</h3><span class="status-chip #effectiveActive ? 'active' : 'archived'#">#$r( "automations.status.#statusKey#" )#</span></div></div></header>
							<div class="automation-rule-flow">
								<div><small>#$r( "automations.when" )#</small><strong>#$r( "automations.rule.enters" )# <span>#encodeForHTML( rule.column_name )#</span></strong><p>#encodeForHTML( rule.board_name )##rule.is_hidden_from_members ? " · " & $r( "automations.hiddenLane" ) : ""#</p></div>
								<svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>
								<div><small>#$r( "automations.then" )#</small><strong>#$r( "automations.rule.notify" )# <span>#encodeForHTML( rule.recipient_name )#</span></strong><p>#$r( "automations.rule.inApp" )#</p></div>
							</div>
							<footer>
								<p>#rule.run_count# #$r( val( rule.run_count ) == 1 ? "automations.run" : "automations.runs" )#<cfif !isNull( rule.last_triggered_at ) && isDate( rule.last_triggered_at )> &middot; #$r( "automations.lastRun" )# #encodeForHTML( dateTimeFormat( rule.last_triggered_at, dateMask ) )#</cfif></p>
								<cfif management.canManage>
									<div class="automation-rule-actions">
										<cfif ( !ruleUnavailable && management.isPremium ) || rule.is_enabled>
											<form method="post" action="/app/automations/#encodeForURL( rule.id )#/toggle" hx-post="/app/automations/#encodeForURL( rule.id )#/toggle" hx-target="##automation-panel" hx-select="##automation-panel" hx-swap="outerHTML" hx-disabled-elt="find button">
												<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.automationCsrfToken )#"><input type="hidden" name="enabled" value="#rule.is_enabled ? 'false' : 'true'#">
												<button class="button button-ghost button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###rule.is_enabled ? 'pause' : 'play'#"></use></svg>#rule.is_enabled ? $r( "automations.pause" ) : $r( "automations.enable" )#</button>
											</form>
										</cfif>
										<form method="post" action="/app/automations/#encodeForURL( rule.id )#/delete" hx-post="/app/automations/#encodeForURL( rule.id )#/delete" hx-target="##automation-panel" hx-select="##automation-panel" hx-swap="outerHTML" hx-disabled-elt="find button" hx-confirm="#encodeForHTMLAttribute( $r( 'automations.removeConfirm' ) )#">
											<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.automationCsrfToken )#"><button class="button button-danger-soft button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##trash"></use></svg><span class="sr-only">#$r( "automations.remove" )#</span></button>
										</form>
									</div>
								</cfif>
							</footer>
						</article>
					</cfloop>
				</div>
			</cfif>
		</section>
	</div>
</section>
</cfoutput>
