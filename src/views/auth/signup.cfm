<cfoutput>
<main class="auth-shell">
    <a class="brand auth-brand" href="/">
        <span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span>
        <span class="brand-name">Tabor<span>Lane</span></span>
    </a>
    <section class="auth-card">
        <a class="auth-back" href="/"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "app.back" )#</a>
        <p class="eyebrow"><span></span>#$r( "nav.signup" )#</p>
        <h1>#$r( "auth.signup.title" )#</h1>
        <p>#$r( "auth.signup.body" )#</p>

        <cfif prc.errors.len()>
            <div class="form-errors" role="alert">
                <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##alert"></use></svg>
                <div><cfloop array="#prc.errors#" item="error"><p>#encodeForHTML( error )#</p></cfloop></div>
            </div>
        </cfif>

        <form class="auth-form" method="post" action="/auth/register">
            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.csrfToken )#">
            <label>#$r( "auth.name" )#
                <input name="displayName" type="text" autocomplete="name" value="#encodeForHTMLAttribute( prc.formData.displayName )#" required maxlength="160">
            </label>
            <label>#$r( "auth.email" )#
                <input name="email" type="email" autocomplete="email" value="#encodeForHTMLAttribute( prc.formData.email )#" placeholder="you@company.com" required maxlength="320">
            </label>
            <label>#$r( "auth.workspaceName" )#
                <input name="workspaceName" type="text" autocomplete="organization" value="#encodeForHTMLAttribute( prc.formData.workspaceName )#" placeholder="#encodeForHTMLAttribute( $r( 'auth.workspacePlaceholder' ) )#" required maxlength="160">
            </label>
            <label>#$r( "auth.password" )#
                <input name="password" type="password" autocomplete="new-password" required minlength="10">
                <small>#$r( "auth.passwordHint" )#</small>
            </label>
            <button class="button button-primary" type="submit">#$r( "auth.createWorkspace" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg></button>
        </form>
        <small class="auth-terms">#$r( "auth.signup.terms" )#</small>
        <p class="auth-switch">#$r( "auth.signup.hasAccount" )# <a href="/login">#$r( "auth.signup.login" )#</a></p>
    </section>
</main>
</cfoutput>
