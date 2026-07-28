<cfoutput>
<main class="auth-shell">
    <a class="brand auth-brand" href="/">
        <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
        <span class="brand-name">Tabor<span>Lane</span></span>
    </a>
    <section class="auth-card">
        <a class="auth-back" href="/"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "app.back" )#</a>
        <p class="eyebrow"><span></span>#$r( "nav.login" )#</p>
        <h1>#$r( "auth.login.title" )#</h1>
        <p>#$r( "auth.login.body" )#</p>

        <cfif prc.errors.len()>
            <div class="form-errors" role="alert">
                <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg>
                <div><cfloop array="#prc.errors#" item="error"><p>#encodeForHTML( error )#</p></cfloop></div>
            </div>
        </cfif>

        <cfif prc.googleOAuthEnabled>
            <a class="button button-outline auth-google" href="/auth/google?invitationToken=#encodeForURL( prc.formData.invitationToken )#">
                <svg class="icon google-icon" aria-hidden="true"><use href="/resources/icons.svg##google"></use></svg>
                #$r( "auth.google" )#
            </a>
            <div class="auth-divider"><span>#$r( "auth.or" )#</span></div>
        </cfif>

        <form class="auth-form" method="post" action="/auth/login">
            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.csrfToken )#">
            <input type="hidden" name="invitationToken" value="#encodeForHTMLAttribute( prc.formData.invitationToken )#">
            <label>#$r( "auth.email" )#
                <input name="email" type="email" autocomplete="email" value="#encodeForHTMLAttribute( prc.formData.email )#" placeholder="you@company.com" required maxlength="320" autofocus>
            </label>
            <label>#$r( "auth.password" )#
                <input name="password" type="password" autocomplete="current-password" required>
            </label>
            <a class="auth-helper-link" href="/forgot-password">#$r( "auth.forgot.link" )#</a>
            <button class="button button-primary" type="submit">#$r( "auth.login.submit" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg></button>
        </form>
        <p class="auth-switch">#$r( "auth.login.noAccount" )# <a href="/signup">#$r( "auth.login.create" )#</a></p>
    </section>
</main>
</cfoutput>
