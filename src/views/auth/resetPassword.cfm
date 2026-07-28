<cfoutput>
<main class="auth-shell">
    <a class="brand auth-brand" href="/"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span><span class="brand-name">Tabor<span>Lane</span></span></a>
    <section class="auth-card">
        <h1>#$r( "auth.reset.title" )#</h1>
        <p>#$r( "auth.reset.body" )#</p>
        <cfif prc.errors.len()><div class="form-errors" role="alert"><svg class="icon"><use href="/resources/icons.svg##alert"></use></svg><div><cfloop array="#prc.errors#" item="error"><p>#encodeForHTML( error )#</p></cfloop></div></div></cfif>
        <form class="auth-form" method="post" action="/auth/reset-password">
            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.csrfToken )#">
            <input type="hidden" name="token" value="#encodeForHTMLAttribute( prc.token )#">
            <label>#$r( "auth.reset.newPassword" )#<input name="password" type="password" autocomplete="new-password" minlength="10" required autofocus><small>#$r( "auth.passwordHint" )#</small></label>
            <button class="button button-primary" type="submit">#$r( "auth.reset.submit" )#</button>
        </form>
    </section>
</main>
</cfoutput>
