<cfscript>
	management = prc.workspaceSettings;
	settings = management.settings;
	invitationPolicy = settings.invitation_policy ?: "owner_admin";
	boardCreationPolicy = settings.board_creation_policy ?: "owner_admin";
	invitationPolicyLabel = invitationPolicy == "owner_admin" ? "ownerAdmin" : "ownerOnly";
	boardCreationPolicyLabel = boardCreationPolicy == "owner_admin" ? "ownerAdmin" : "ownerOnly";
</cfscript>
<cfoutput>
<cfif prc.isHtmxRequest><title>#encodeForHTML( prc.pageTitle )#</title></cfif>
<section id="workspace-main" class="workspace-main settings-main"
	data-workspace-page="settings"
	data-workspace-name="#encodeForHTMLAttribute( settings.name )#"
	data-workspace-role="#encodeForHTMLAttribute( management.role )#"
	data-workspace-role-label="#encodeForHTMLAttribute( $r( 'workspace.role.#management.role#', management.role ) )#">
	<header class="workspace-header settings-header">
		<div>
			<small>#$r( "settings.eyebrow" )#</small>
			<h1>#$r( "settings.title" )#</h1>
			<p>#$r( "settings.body" )#</p>
		</div>
		<span class="settings-role-chip"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##shield-check"></use></svg> #encodeForHTML( $r( "workspace.role.#management.role#", management.role ) )#</span>
	</header>

	<cfif prc.notice.len()>
		<div class="form-success settings-feedback" role="status"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg><p>#$r( "settings.notice.#prc.notice#" )#</p></div>
	</cfif>
	<cfif prc.error.len()>
		<div class="form-errors settings-feedback" role="alert"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg><p>#$r( "settings.error.#prc.error#" )#</p></div>
	</cfif>

	<div class="settings-grid">
		<section class="management-panel settings-panel" aria-labelledby="settings-general-title">
			<div class="panel-heading settings-panel-heading">
				<div class="settings-heading-copy">
					<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##building"></use></svg></span>
					<div><h2 id="settings-general-title">#$r( "settings.general.title" )#</h2><p>#$r( "settings.general.body" )#</p></div>
				</div>
				<cfif !management.canEditGeneral><span class="status-chip archived">#$r( "settings.readOnly" )#</span></cfif>
			</div>

			<cfif management.canEditGeneral>
				<form class="management-form settings-form" method="post" action="/app/settings/general"
					hx-post="/app/settings/general" hx-target="##workspace-main" hx-select="##workspace-main"
					hx-swap="outerHTML show:top" hx-disabled-elt="find button">
					<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.settingsCsrfToken )#">
					<label>#$r( "settings.general.name" )#<input name="name" value="#encodeForHTMLAttribute( settings.name )#" required maxlength="160" autocomplete="organization"></label>
					<label>#$r( "settings.general.slug" )#<input name="slug" value="#encodeForHTMLAttribute( settings.slug )#" required minlength="3" maxlength="100" pattern="[a-z0-9]+(?:-[a-z0-9]+)*" autocomplete="off"><small>#$r( "settings.general.slugHint" )#</small></label>
					<label>#$r( "settings.general.timezone" )#<input name="timezone" value="#encodeForHTMLAttribute( settings.timezone )#" required maxlength="64" list="workspace-timezones" autocomplete="off"><small>#$r( "settings.general.timezoneHint" )#</small></label>
					<datalist id="workspace-timezones"><cfloop array="#management.timezoneSuggestions#" item="timezone"><option value="#encodeForHTMLAttribute( timezone )#"></cfloop></datalist>
					<label>#$r( "settings.general.defaultLanguage" )#<select name="defaultLocale"><option value="en_US" #settings.default_locale == "en_US" ? "selected" : ""#>#$r( "settings.language.en_US" )#</option><option value="pt_BR" #settings.default_locale == "pt_BR" ? "selected" : ""#>#$r( "settings.language.pt_BR" )#</option></select><small>#$r( "settings.general.languageHint" )#</small></label>
					<button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg> #$r( "settings.general.save" )#</button>
				</form>
			<cfelse>
				<dl class="settings-readonly-list">
					<div><dt>#$r( "settings.general.name" )#</dt><dd>#encodeForHTML( settings.name )#</dd></div>
					<div><dt>#$r( "settings.general.slug" )#</dt><dd>#encodeForHTML( settings.slug )#</dd></div>
					<div><dt>#$r( "settings.general.timezone" )#</dt><dd>#encodeForHTML( settings.timezone )#</dd></div>
					<div><dt>#$r( "settings.general.defaultLanguage" )#</dt><dd>#$r( "settings.language.#settings.default_locale#" )#</dd></div>
				</dl>
			</cfif>
		</section>

		<section class="management-panel settings-panel" aria-labelledby="settings-security-title">
			<div class="panel-heading settings-panel-heading">
				<div class="settings-heading-copy">
					<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##shield-check"></use></svg></span>
					<div><h2 id="settings-security-title">#$r( "settings.security.title" )#</h2><p>#$r( "settings.security.body" )#</p></div>
				</div>
				<cfif !management.canManageSecurity><span class="status-chip archived">#$r( "settings.ownerOnly" )#</span></cfif>
			</div>

			<div class="settings-protection-list">
				<div><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##mail"></use></svg></span><div><strong>#$r( "settings.security.verifiedEmail" )#</strong><small>#$r( "settings.security.verifiedEmailBody" )#</small></div><svg class="icon settings-protection-check" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg></div>
				<div><span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg></span><div><strong>#$r( "settings.security.roleProtection" )#</strong><small>#$r( "settings.security.roleProtectionBody" )#</small></div><svg class="icon settings-protection-check" aria-hidden="true"><use href="/resources/icons.svg##check"></use></svg></div>
			</div>

			<cfif management.canManageSecurity>
				<form class="management-form settings-form security-policy-form" method="post" action="/app/settings/security"
					hx-post="/app/settings/security" hx-target="##workspace-main" hx-select="##workspace-main"
					hx-swap="outerHTML show:top" hx-disabled-elt="find button">
					<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.settingsCsrfToken )#">
					<label>#$r( "settings.security.invitations" )#<select name="invitationPolicy"><option value="owner_admin" #invitationPolicy == "owner_admin" ? "selected" : ""#>#$r( "settings.policy.ownerAdmin" )#</option><option value="owner_only" #invitationPolicy == "owner_only" ? "selected" : ""#>#$r( "settings.policy.ownerOnly" )#</option></select><small>#$r( "settings.security.invitationsHint" )#</small></label>
					<label>#$r( "settings.security.boardCreation" )#<select name="boardCreationPolicy"><option value="owner_admin" #boardCreationPolicy == "owner_admin" ? "selected" : ""#>#$r( "settings.policy.ownerAdmin" )#</option><option value="owner_only" #boardCreationPolicy == "owner_only" ? "selected" : ""#>#$r( "settings.policy.ownerOnly" )#</option></select><small>#$r( "settings.security.boardCreationHint" )#</small></label>
					<button class="button button-primary button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg> #$r( "settings.security.save" )#</button>
				</form>
			<cfelse>
				<dl class="settings-readonly-list settings-policy-summary">
					<div><dt>#$r( "settings.security.invitations" )#</dt><dd>#$r( "settings.policy.#invitationPolicyLabel#" )#</dd></div>
					<div><dt>#$r( "settings.security.boardCreation" )#</dt><dd>#$r( "settings.policy.#boardCreationPolicyLabel#" )#</dd></div>
				</dl>
			</cfif>
		</section>
	</div>

	<section class="management-panel settings-panel settings-integrations-entry" aria-labelledby="settings-integrations-title">
		<div class="panel-heading settings-panel-heading">
			<div class="settings-heading-copy">
				<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##link"></use></svg></span>
				<div><h2 id="settings-integrations-title">#$r( "settings.integrations.title" )#</h2><p>#$r( "settings.integrations.body" )#</p></div>
			</div>
			<a class="button button-ghost button-small" href="/app/settings/integrations" hx-get="/app/settings/integrations" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true">
				#$r( "settings.integrations.open" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg>
			</a>
		</div>
		<div class="settings-integration-capabilities" aria-label="#encodeForHTMLAttribute( $r( 'settings.integrations.capabilities' ) )#">
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg> #$r( "integrations.tokens.title" )#</span>
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##bolt"></use></svg> #$r( "integrations.webhooks.title" )#</span>
			<span><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##shield-check"></use></svg> HMAC SHA-256</span>
		</div>
	</section>

	<section class="management-panel settings-panel ownership-panel" aria-labelledby="settings-ownership-title">
		<div class="panel-heading settings-panel-heading">
			<div class="settings-heading-copy">
				<span class="ownership-heading-icon"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg></span>
				<div><h2 id="settings-ownership-title">#$r( "settings.ownership.title" )#</h2><p>#$r( "settings.ownership.body" )#</p></div>
			</div>
			<span class="settings-sensitive-chip"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg> #$r( "settings.ownership.sensitive" )#</span>
		</div>

		<cfif management.canManageSecurity>
			<cfif !settings.has_password>
				<div class="settings-action-message"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg><div><strong>#$r( "settings.ownership.passwordRequired" )#</strong><p>#$r( "settings.ownership.passwordRequiredBody" )#</p><a href="/app/profile" hx-get="/app/profile" hx-target="##workspace-main" hx-select="##workspace-main" hx-swap="outerHTML show:top" hx-push-url="true">#$r( "settings.ownership.openProfile" )#</a></div></div>
			<cfelseif !management.transferCandidates.len()>
				<div class="settings-action-message"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg><div><strong>#$r( "settings.ownership.noCandidates" )#</strong><p>#$r( "settings.ownership.noCandidatesBody" )#</p></div></div>
			<cfelse>
				<form class="management-form ownership-form" method="post" action="/app/settings/ownership"
					hx-post="/app/settings/ownership" hx-target="##workspace-main" hx-select="##workspace-main"
					hx-swap="outerHTML show:top" hx-confirm="#encodeForHTMLAttribute( $r( 'settings.ownership.confirm' ) )#"
					hx-disabled-elt="find button">
					<input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.ownershipCsrfToken )#">
					<label>#$r( "settings.ownership.newOwner" )#<select name="targetUserId" required><option value="">#$r( "settings.ownership.choose" )#</option><cfloop array="#management.transferCandidates#" item="candidate"><option value="#encodeForHTMLAttribute( candidate.id )#">#encodeForHTML( candidate.display_name )# (#encodeForHTML( candidate.email )#) — #encodeForHTML( $r( "workspace.role.#candidate.role#", candidate.role ) )#</option></cfloop></select></label>
					<label>#$r( "settings.ownership.currentPassword" )#<input name="currentPassword" type="password" required autocomplete="current-password"><small>#$r( "settings.ownership.passwordHint" )#</small></label>
					<button class="button button-danger-soft button-small" type="submit"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg> #$r( "settings.ownership.transfer" )#</button>
				</form>
			</cfif>
		<cfelse>
			<div class="settings-action-message"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##lock"></use></svg><div><strong>#$r( "settings.ownership.ownerOnlyTitle" )#</strong><p>#$r( "settings.ownership.ownerOnlyBody" )#</p></div></div>
		</cfif>
	</section>
</section>
</cfoutput>
