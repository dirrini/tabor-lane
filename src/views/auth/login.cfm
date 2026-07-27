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
        <button class="button button-outline auth-google" type="button">G&nbsp;&nbsp; #$r( "auth.google" )#</button>
        <div class="auth-divider"><span>#$r( "auth.or" )#</span></div>
        <form class="auth-form" onsubmit="return false">
            <label>#$r( "auth.email" )#<input type="email" autocomplete="email" placeholder="you@company.com"></label>
            <label>#$r( "auth.password" )#<input type="password" autocomplete="current-password" placeholder="••••••••"></label>
            <button class="button button-primary" type="submit">#$r( "auth.continue" )# <svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##arrow-right"></use></svg></button>
        </form>
        <small class="auth-preview">#$r( "auth.preview" )#</small>
        <p class="auth-switch">#$r( "auth.login.noAccount" )# <a href="/signup">#$r( "auth.login.create" )#</a></p>
    </section>
</main>
</cfoutput>
