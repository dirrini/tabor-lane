<cfoutput>
<main class="auth-shell">
    <a class="brand auth-brand" href="/"><span class="brand-mark" aria-hidden="true"><i></i><i></i><i></i></span><span class="brand-name">Tabor<span>Lane</span></span></a>
    <section class="auth-card auth-state-card">
        <span class="auth-state-icon"><svg class="icon" aria-hidden="true"><use href="/resources/icons.svg##users"></use></svg></span>
        <cfif !prc.invitation.found>
            <h1>#$r( "invite.invalid.title" )#</h1><p>#$r( "invite.invalid.body" )#</p><a class="button button-primary" href="/">#$r( "app.back" )#</a>
        <cfelseif prc.wrongAccount>
            <h1>#$r( "invite.wrong.title" )#</h1><p>#replace( $r( "invite.wrong.body" ), "{email}", encodeForHTML( prc.invitation.email ) )#</p>
        <cfelse>
            <h1>#$r( "invite.title" )#</h1>
            <p>#replace( replace( $r( "invite.body" ), "{inviter}", encodeForHTML( prc.invitation.inviterName ) ), "{workspace}", encodeForHTML( prc.invitation.workspaceName ) )#</p>
            <div class="auth-state-actions">
                <a class="button button-primary" href="/signup?invitationToken=#encodeForURL( prc.invitationToken )#">#$r( "invite.create" )#</a>
                <a class="button button-ghost" href="/login?invitationToken=#encodeForURL( prc.invitationToken )#">#$r( "invite.login" )#</a>
            </div>
        </cfif>
    </section>
</main>
</cfoutput>
