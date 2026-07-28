<cfoutput>
<main class="auth-shell">
    <a class="brand auth-brand" href="/"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span><span class="brand-name">Tabor<span>Lane</span></span></a>
    <section class="auth-card">
        <a class="auth-back" href="/login"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-left"></use></svg> #$r( "auth.login.title" )#</a>
        <h1>#$r( "auth.forgot.title" )#</h1>
        <p>#$r( "auth.forgot.body" )#</p>
        <cfif prc.errors.len()><div class="form-errors" role="alert"><svg class="icon"><use href="/resources/icons.svg##alert"></use></svg><div><cfloop array="#prc.errors#" item="error"><p>#encodeForHTML( error )#</p></cfloop></div></div></cfif>
        <cfif prc.sent>
            <div class="form-success">#$r( "auth.forgot.sent" )#</div>
            <cfif prc.developmentToken.len()><a class="auth-preview button button-primary" href="/reset-password/#encodeForURL( prc.developmentToken )#">#$r( "auth.forgot.development" )#</a></cfif>
        <cfelse>
            <form class="auth-form" method="post" action="/auth/forgot-password">
                <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.csrfToken )#">
                <label>#$r( "auth.email" )#<input name="email" type="email" autocomplete="email" value="#encodeForHTMLAttribute( prc.formData.email )#" required autofocus></label>
                <button class="button button-primary" type="submit">#$r( "auth.forgot.submit" )#</button>
            </form>
        </cfif>
    </section>
</main>
</cfoutput>
