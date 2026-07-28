<cfoutput>
<main class="auth-shell">
    <a class="brand auth-brand" href="/">
        <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
        <span class="brand-name">Tabor<span>Lane</span></span>
    </a>
    <section class="auth-card">
        <a class="auth-back" href="/login"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "auth.google.onboarding.back" )#</a>
        <p class="eyebrow"><span></span>#$r( "auth.google.onboarding.eyebrow" )#</p>
        <h1>#$r( "auth.google.onboarding.title" )#</h1>
        <p>#$r( "auth.google.onboarding.body" )#</p>

        <cfif prc.errors.len()>
            <div class="form-errors" role="alert">
                <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg>
                <div><cfloop array="#prc.errors#" item="error"><p>#encodeForHTML( error )#</p></cfloop></div>
            </div>
        </cfif>

        <div class="google-profile">
            <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##google"></use></svg>
            <span><strong>#encodeForHTML( prc.profile.email )#</strong><small>#$r( "auth.google.verified" )#</small></span>
        </div>

        <form class="auth-form" method="post" action="/auth/google/complete">
            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.csrfToken )#">
            <label>#$r( "auth.name" )#
                <input name="displayName" type="text" autocomplete="name" value="#encodeForHTMLAttribute( prc.formData.displayName )#" required maxlength="160" autofocus>
            </label>
            <cfif prc.invitation.found>
                <div class="invitation-summary"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg><span>#$r( "invite.joining" )# <strong>#encodeForHTML( prc.invitation.workspaceName )#</strong></span></div>
            <cfelse>
                <label>#$r( "auth.workspaceName" )#
                    <input name="workspaceName" type="text" autocomplete="organization" value="#encodeForHTMLAttribute( prc.formData.workspaceName )#" placeholder="#encodeForHTMLAttribute( $r( 'auth.workspacePlaceholder' ) )#" required maxlength="160">
                </label>
            </cfif>
            <button class="button button-primary" type="submit">#$r( "auth.google.onboarding.submit" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg></button>
        </form>
    </section>
</main>
</cfoutput>
