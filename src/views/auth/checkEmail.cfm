<cfoutput>
<main class="auth-shell">
    <a class="brand auth-brand" href="/"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span><span class="brand-name">Tabor<span>Lane</span></span></a>
    <section class="auth-card auth-state-card">
        <span class="auth-state-icon"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##mail"></use></svg></span>
        <h1>#$r( "auth.verify.title" )#</h1>
        <p>#replace( $r( "auth.verify.body" ), "{email}", encodeForHTML( prc.auth.email ) )#</p>
        <cfif prc.developmentToken.len()>
            <a class="auth-preview button button-primary" data-development-verification href="/verify-email/#encodeForURL( prc.developmentToken )#">#$r( "auth.verify.development" )#</a>
        </cfif>
        <form method="post" action="/auth/resend-verification">
            <input type="hidden" name="csrfToken" value="#encodeForHTMLAttribute( prc.csrfToken )#">
            <button class="button button-ghost" type="submit">#$r( "auth.verify.resend" )#</button>
        </form>
    </section>
</main>
</cfoutput>
