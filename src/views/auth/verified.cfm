<cfoutput>
<main class="auth-shell">
    <a class="brand auth-brand" href="/"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span><span class="brand-name">Tabor<span>Lane</span></span></a>
    <section class="auth-card auth-state-card">
        <span class="auth-state-icon #prc.success ? 'success' : 'error'#"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg###prc.success ? 'check' : 'alert'#"></use></svg></span>
        <h1>#prc.success ? $r( "auth.verified.title" ) : $r( "auth.verify.invalidTitle" )#</h1>
        <p>#prc.success ? $r( "auth.verified.body" ) : $r( "auth.verify.invalidBody" )#</p>
        <a class="button button-primary" href="#prc.success && structKeyExists( session, 'auth' ) ? '/app' : '/login'#">#$r( "auth.continue" )#</a>
    </section>
</main>
</cfoutput>
