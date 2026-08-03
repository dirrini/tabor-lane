<cfscript>
	management = prc.integrations;
	scopeLabels = {
		"boards:read"="boardsRead",
		"cards:read"="cardsRead",
		"cards:create"="cardsCreate",
		"cards:update"="cardsUpdate",
		"cards:move"="cardsMove"
	};
	eventLabels = {
		"card.created"="cardCreated",
		"card.updated"="cardUpdated",
		"card.assigned"="cardAssigned",
		"card.moved"="cardMoved",
		"card.reordered"="cardReordered",
		"card.archived"="cardArchived",
		"card.blocked"="cardBlocked",
		"card.unblocked"="cardUnblocked",
		"card.completed"="cardCompleted",
		"card.reopened"="cardReopened"
	};

	string function integrationDateLabel( any value="" ){
		if ( isNull( arguments.value ) || !isDate( arguments.value ) ) {
			return $r( "integrations.tokens.never" );
		}
		return dateTimeFormat(
			arguments.value,
			getFWLocale() == "pt_BR" ? "dd/MM/yyyy HH:mm" : "mmm d, yyyy HH:mm"
		);
	}

	boolean function rowHasDate( required struct row, required string key ){
		return structKeyExists( arguments.row, arguments.key )
			&& !isNull( arguments.row[ arguments.key ] )
			&& isDate( arguments.row[ arguments.key ] );
	}

	string function replaceIntegrationTokens( required string value, required struct tokens ){
		var result = arguments.value;
		for ( var tokenName in arguments.tokens ) {
			result = replace( result, "{#tokenName#}", toString( arguments.tokens[ tokenName ] ), "all" );
		}
		return result;
	}
</cfscript>
<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
<section id="workspace-main" class="workspace-main settings-main integrations-main"
	data-workspace-page="integrations"
	data-workspace-name="#encodeForHTMLAttribute( prc.auth.workspaceName )#"
	data-workspace-role="#encodeForHTMLAttribute( management.role )#"
	data-workspace-role-label="#encodeForHTMLAttribute( $r( 'workspace.role.#management.role#', management.role ) )#">
	<header class="workspace-header settings-header integrations-header">
		<div>
			<a class="integrations-back" href="/app/settings" hx-get="/app/settings" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "integrations.back" )#</a>
			<small>#$r( "integrations.eyebrow" )#</small>
			<h1>#$r( "integrations.title" )#</h1>
			<p>#$r( "integrations.body" )#</p>
		</div>
		<div class="integrations-header-meta">
			<span class="settings-role-chip"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##shield-check"></use></svg> #encodeForHTML( $r( "workspace.role.#management.role#", management.role ) )#</span>
			<span>#encodeForHTML( replaceIntegrationTokens( $r( "integrations.usage" ), {
				tokens=management.activeTokenCount,
				tokenLimit=management.tokenLimit,
				webhooks=management.activeEndpointCount,
				webhookLimit=management.endpointLimit
			} ) )#</span>
		</div>
	</header>

	<cfif prc.notice.len()>
		<div class="form-success settings-feedback" role="status"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg><p>#$r( "integrations.notice.#prc.notice#" )#</p></div>
	</cfif>
	<cfif prc.error.len()>
		<div class="form-errors settings-feedback" role="alert"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "integrations.error.#prc.error#" )#</p></div>
	</cfif>

	<cfif prc.integrationReveal.count()>
		<section class="integration-secret-reveal" data-integration-reveal data-copied-label="#encodeForHTMLAttribute( $r( 'integrations.reveal.copied' ) )#" aria-labelledby="integration-reveal-title">
			<div><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg></div>
			<section>
				<small>#encodeForHTML( prc.integrationReveal.name ?: "" )#</small>
				<h2 id="integration-reveal-title">#$r( "integrations.reveal.#prc.integrationReveal.kind#Title" )#</h2>
				<p>#$r( "integrations.reveal.body" )#</p>
				<div class="integration-secret-value"><code data-integration-secret>#encodeForHTML( prc.integrationReveal.value )#</code><button class="button button-primary button-small" type="button" data-integration-copy><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##copy"></use></svg><span>#$r( "integrations.reveal.copy" )#</span></button></div>
			</section>
		</section>
	</cfif>

	<cfif !management.canManage>
		<div class="settings-action-message integration-access-message"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg><div><strong>#$r( "integrations.ownerAdminOnly" )#</strong><p>#$r( "integrations.ownerAdminOnlyBody" )#</p></div></div>
	<cfelse>
		<div class="integration-management-grid">
			<section class="management-panel settings-panel integration-create-panel" aria-labelledby="integration-token-create-title">
				<div class="panel-heading settings-panel-heading"><div class="settings-heading-copy"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg></span><div><h2 id="integration-token-create-title">#$r( "integrations.tokens.create" )#</h2><p>#$r( "integrations.tokens.body" )#</p></div></div></div>
				<form class="management-form integration-form" method="post" action="/app/settings/integrations/tokens" hx-post="/app/settings/integrations/tokens" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-disabled-elt="find button">
					<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.integrationsCsrfToken )#">
					<label>#$r( "integrations.tokens.name" )#<input name="name" required maxlength="120" placeholder="#encodeForHTMLAttribute( $r( 'integrations.tokens.namePlaceholder' ) )#" autocomplete="off"></label>
					<fieldset><legend>#$r( "integrations.tokens.scopes" )#</legend><div class="integration-check-grid"><cfloop array="#management.scopes#" item="scope"><label><input type="checkbox" name="scopes" value="#encodeForHTMLAttribute( scope )#" checked><span>#$r( "integrations.scope.#scopeLabels[ scope ]#" )#<small>#encodeForHTML( scope )#</small></span></label></cfloop></div></fieldset>
					<label>#$r( "integrations.tokens.expiry" )#<select name="expirationDays"><option value="30">#$r( "integrations.tokens.expiry30" )#</option><option value="90" selected>#$r( "integrations.tokens.expiry90" )#</option><option value="365">#$r( "integrations.tokens.expiry365" )#</option></select></label>
					<button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "integrations.tokens.createAction" )#</button>
				</form>
			</section>

			<section class="management-panel settings-panel integration-list-panel" aria-labelledby="integration-token-list-title">
				<div class="panel-heading settings-panel-heading"><div class="settings-heading-copy"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##list-checks"></use></svg></span><div><h2 id="integration-token-list-title">#$r( "integrations.tokens.active" )#</h2><p>#$r( "integrations.tokens.body" )#</p></div></div></div>
				<div class="integration-token-list">
					<cfif !management.tokens.len()><p class="integration-empty">#$r( "integrations.tokens.empty" )#</p></cfif>
					<cfloop array="#management.tokens#" item="apiToken">
						<cfset tokenRevoked=rowHasDate( apiToken, "revoked_at" )><cfset tokenExpired=!tokenRevoked && dateCompare( apiToken.expires_at, now() ) < 0>
						<article class="#tokenRevoked || tokenExpired ? 'is-inactive' : ''#" data-api-token-id="#encodeForHTMLAttribute( apiToken.id )#">
							<header><div><strong>#encodeForHTML( apiToken.name )#</strong><code>#encodeForHTML( apiToken.token_prefix )#</code></div><span class="status-chip #tokenRevoked || tokenExpired ? 'archived' : 'active'#">#$r( tokenRevoked ? "integrations.tokens.revoked" : ( tokenExpired ? "integrations.tokens.expired" : "integrations.webhooks.enabled" ) )#</span></header>
							<div class="integration-chip-list"><cfloop list="#apiToken.scopes_csv#" item="tokenScope"><span>#encodeForHTML( tokenScope )#</span></cfloop></div>
							<footer><dl><div><dt>#$r( "integrations.tokens.expires" )#</dt><dd>#encodeForHTML( integrationDateLabel( apiToken.expires_at ) )#</dd></div><div><dt>#$r( "integrations.tokens.lastUsed" )#</dt><dd>#encodeForHTML( integrationDateLabel( apiToken.last_used_at ?: "" ) )#</dd></div></dl><cfif !tokenRevoked && !tokenExpired><form method="post" action="/app/settings/integrations/tokens/#encodeForURL( apiToken.id )#/revoke" hx-post="/app/settings/integrations/tokens/#encodeForURL( apiToken.id )#/revoke" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-confirm="#encodeForHTMLAttribute( $r( 'integrations.tokens.revokeConfirm' ) )#" hx-disabled-elt="find button"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.integrationsCsrfToken )#"><input type="hidden" name="tokenId" value="#encodeForHTMLAttribute( apiToken.id )#"><button class="button button-danger-soft button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##trash"></use></svg> #$r( "integrations.tokens.revoke" )#</button></form></cfif></footer>
						</article>
					</cfloop>
				</div>
			</section>

			<section class="management-panel settings-panel integration-create-panel" aria-labelledby="integration-webhook-create-title">
				<div class="panel-heading settings-panel-heading"><div class="settings-heading-copy"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg></span><div><h2 id="integration-webhook-create-title">#$r( "integrations.webhooks.create" )#</h2><p>#$r( "integrations.webhooks.body" )#</p></div></div></div>
				<form class="management-form integration-form" method="post" action="/app/settings/integrations/webhooks" hx-post="/app/settings/integrations/webhooks" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-disabled-elt="find button">
					<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.integrationsCsrfToken )#">
					<label>#$r( "integrations.webhooks.name" )#<input name="name" required maxlength="120" placeholder="#encodeForHTMLAttribute( $r( 'integrations.webhooks.namePlaceholder' ) )#" autocomplete="off"></label>
					<label>#$r( "integrations.webhooks.url" )#<input name="endpointUrl" type="url" required maxlength="2048" placeholder="https://example.com/webhooks/taborlane" autocomplete="url"><small>#$r( "integrations.webhooks.urlHint" )#</small></label>
					<fieldset><legend>#$r( "integrations.webhooks.events" )#</legend><div class="integration-check-grid integration-event-grid"><cfloop array="#management.eventTypes#" item="eventType"><label><input type="checkbox" name="eventTypes" value="#encodeForHTMLAttribute( eventType )#" #listFindNoCase( 'card.created,card.updated,card.moved,card.completed', eventType ) ? 'checked' : ''#><span>#$r( "integrations.event.#eventLabels[ eventType ]#" )#<small>#encodeForHTML( eventType )#</small></span></label></cfloop></div></fieldset>
					<button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##plus"></use></svg> #$r( "integrations.webhooks.createAction" )#</button>
				</form>
			</section>

			<section class="management-panel settings-panel integration-list-panel" aria-labelledby="integration-webhook-list-title">
				<div class="panel-heading settings-panel-heading"><div class="settings-heading-copy"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##link"></use></svg></span><div><h2 id="integration-webhook-list-title">#$r( "integrations.webhooks.endpoints" )#</h2><p>#$r( "integrations.webhooks.body" )#</p></div></div></div>
				<div class="integration-endpoint-list">
					<cfif !management.endpoints.len()><p class="integration-empty">#$r( "integrations.webhooks.empty" )#</p></cfif>
					<cfloop array="#management.endpoints#" item="endpoint">
						<article data-webhook-endpoint-id="#encodeForHTMLAttribute( endpoint.id )#"><header><div><strong>#encodeForHTML( endpoint.name )#</strong><code>#encodeForHTML( endpoint.url )#</code></div><span class="status-chip #endpoint.is_enabled ? 'active' : 'archived'#">#$r( endpoint.is_enabled ? "integrations.webhooks.enabled" : "integrations.webhooks.disabled" )#</span></header><div class="integration-chip-list"><cfloop list="#endpoint.event_types_csv#" item="endpointEvent"><span>#encodeForHTML( endpointEvent )#</span></cfloop></div><p>#encodeForHTML( replace( $r( 'integrations.webhooks.secretHint' ), '{hint}', endpoint.secret_hint, 'all' ) )# · #$r( "integrations.webhooks.lastSuccess" )#: #encodeForHTML( integrationDateLabel( endpoint.last_success_at ?: "" ) )#</p><footer><form method="post" action="/app/settings/integrations/webhooks/#encodeForURL( endpoint.id )#/test" hx-post="/app/settings/integrations/webhooks/#encodeForURL( endpoint.id )#/test" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-disabled-elt="find button"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.integrationsCsrfToken )#"><input type="hidden" name="endpointId" value="#encodeForHTMLAttribute( endpoint.id )#"><button class="button button-ghost button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##play"></use></svg> #$r( "integrations.webhooks.test" )#</button></form><form method="post" action="/app/settings/integrations/webhooks/#encodeForURL( endpoint.id )#/toggle" hx-post="/app/settings/integrations/webhooks/#encodeForURL( endpoint.id )#/toggle" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-disabled-elt="find button"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.integrationsCsrfToken )#"><input type="hidden" name="endpointId" value="#encodeForHTMLAttribute( endpoint.id )#"><input type="hidden" name="enabled" value="#endpoint.is_enabled ? 'false' : 'true'#"><button class="button button-ghost button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###endpoint.is_enabled ? 'pause' : 'play'#"></use></svg> #$r( endpoint.is_enabled ? "integrations.webhooks.disable" : "integrations.webhooks.enable" )#</button></form><form method="post" action="/app/settings/integrations/webhooks/#encodeForURL( endpoint.id )#/delete" hx-post="/app/settings/integrations/webhooks/#encodeForURL( endpoint.id )#/delete" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-confirm="#encodeForHTMLAttribute( $r( 'integrations.webhooks.deleteConfirm' ) )#" hx-disabled-elt="find button"><input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.integrationsCsrfToken )#"><input type="hidden" name="endpointId" value="#encodeForHTMLAttribute( endpoint.id )#"><button class="button button-danger-soft button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##trash"></use></svg> #$r( "integrations.webhooks.delete" )#</button></form></footer></article>
					</cfloop>
				</div>
			</section>
		</div>
	</cfif>

	<section class="management-panel settings-panel integration-delivery-panel" aria-labelledby="integration-delivery-title">
		<div class="panel-heading settings-panel-heading"><div class="settings-heading-copy"><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##clock"></use></svg></span><div><h2 id="integration-delivery-title">#$r( "integrations.deliveries.title" )#</h2><p>#$r( "integrations.deliveries.body" )#</p></div></div></div>
		<div class="integration-delivery-list">
			<cfif !management.deliveries.len()><p class="integration-empty">#$r( "integrations.deliveries.empty" )#</p></cfif>
			<cfloop array="#management.deliveries#" item="delivery">
				<cfset deliveryStatus=rowHasDate( delivery, "delivered_at" ) ? "delivered" : ( rowHasDate( delivery, "failed_at" ) ? "failed" : "pending" )>
				<article data-webhook-delivery-id="#encodeForHTMLAttribute( delivery.id )#"><span class="delivery-status delivery-#deliveryStatus#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###deliveryStatus == 'delivered' ? 'check' : ( deliveryStatus == 'failed' ? 'alert' : 'clock' )#"></use></svg></span><div><strong>#encodeForHTML( delivery.event_type )#</strong><small>#encodeForHTML( delivery.endpoint_name )# · #encodeForHTML( integrationDateLabel( delivery.created_at ) )#</small><cfif len( trim( delivery.last_error ?: "" ) )><p>#encodeForHTML( delivery.last_error )#</p></cfif></div><dl><div><dt>#$r( "integrations.deliveries.#deliveryStatus#" )#</dt><dd><cfif structKeyExists( delivery, "last_http_status" ) && !isNull( delivery.last_http_status )>#encodeForHTML( replace( $r( 'integrations.deliveries.http' ), '{status}', delivery.last_http_status, 'all' ) )#<cfelse>—</cfif></dd></div><div><dt>#$r( "integrations.deliveries.attemptCount" )#</dt><dd>#encodeForHTML( replace( $r( 'integrations.deliveries.attempts' ), '{count}', delivery.attempts, 'all' ) )#</dd></div></dl></article>
			</cfloop>
		</div>
	</section>

	<section class="integration-docs-card"><div><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##info"></use></svg></div><div><h2>#$r( "integrations.docs.title" )#</h2><p>#encodeForHTML( $r( "integrations.docs.body" ) )#</p><code>GET /api/v1/boards</code><code>GET /api/v1/boards/{boardId}/cards</code><code>POST /api/v1/cards</code><p>#encodeForHTML( $r( "integrations.docs.signature" ) )#</p></div></section>
</section>
</cfoutput>
