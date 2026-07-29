component {

    property name="authService" inject="AuthService";
    property name="stripeBillingService" inject="StripeBillingService";
    property name="notificationService" inject="NotificationService";
    property name="rateLimitService" inject="RateLimitService";
    property name="workspaceViewService" inject="WorkspaceViewService";

    this.allowedMethods = {
        index = "GET",
        update = "POST",
        changePassword = "POST"
    };

    function preHandler( event, rc, prc, action, eventArguments ) {
        if ( !structKeyExists( session, "auth" ) ) relocate( uri = "/login" );
        session.auth.emailVerified = authService.isEmailVerified( session.auth.id );
        if ( !session.auth.emailVerified ) relocate( uri = "/check-email" );
        prc.auth = session.auth;
    }

    function index( event, rc, prc ) {
        prc.page = "profile";
        prc.pageTitle = $r( "profile.title" );
        prc.profile = authService.getProfile( prc.auth.id, prc.auth.workspaceId );
        if ( !prc.profile.found ) relocate( uri = "/app" );
        prc.account = prc.profile.data;
        prc.billing = stripeBillingService.getBilling( prc.auth.id, prc.auth.workspaceId );
        if (
            prc.billing.plan == "premium"
            && prc.billing.subscriptionId.len()
            && !isDate( prc.billing.currentPeriodEnd )
        ) {
            stripeBillingService.reconcileBilling( prc.auth.id, prc.auth.workspaceId );
            prc.billing = stripeBillingService.getBilling( prc.auth.id, prc.auth.workspaceId );
        }
        prc.pricing = stripeBillingService.getPricing(
            prc.auth.locale ?: "en_US",
            prc.billing.memberCount ?: 1
        );
        prc.profileCsrfToken = csrfGenerateToken( "profile" );
        prc.passwordCsrfToken = csrfGenerateToken( "profile-password" );
        prc.billingCsrfToken = csrfGenerateToken( "billing" );
        prc.billingPortalCsrfToken = csrfGenerateToken( "billing-portal" );
        prc.logoutCsrfToken = csrfGenerateToken( "logout" );
        prc.checkoutNotice = rc.checkout ?: "";
        prc.notice = rc.updated ?: rc.passwordChanged ?: "";
        prc.error = rc.error ?: "";
        workspaceViewService.render( event, prc, "app/profile" );
    }

    function update( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "profile" ) ) {
            relocate( uri = "/app/profile?error=expired" );
        }
        var result = authService.updateProfile(
            userId = prc.auth.id,
            displayName = rc.displayName ?: "",
            email = rc.email ?: "",
            locale = rc.locale ?: "en_US"
        );
        if ( !result.success ) {
            relocate( uri = "/app/profile?error=#urlEncodedFormat( result.code )#" );
        }
        session.auth.displayName = result.user.displayName;
        session.auth.email = result.user.email;
        session.auth.locale = result.user.locale;
        session.auth.emailVerified = result.user.emailVerified;
        setFWLocale( result.user.locale );
        if ( result.emailChanged ) {
            notificationService.sendEmailVerification( result.user, result.verificationToken );
            relocate( uri = "/check-email?sent=1" );
        }
        relocate( uri = "/app/profile?updated=1" );
    }

    function changePassword( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "profile-password" ) ) {
            relocate( uri = "/app/profile?error=expired" );
        }
        if ( !rateLimitService.allow( "profile-password:#prc.auth.id#", 5, 3600 ) ) {
            relocate( uri = "/app/profile?error=rate" );
        }
        if ( ( rc.newPassword ?: "" ) != ( rc.confirmPassword ?: "" ) ) {
            relocate( uri = "/app/profile?error=password_match" );
        }
        var result = authService.changePassword(
            userId = prc.auth.id,
            currentPassword = rc.currentPassword ?: "",
            newPassword = rc.newPassword ?: ""
        );
        if ( !result.success ) {
            relocate( uri = "/app/profile?error=#urlEncodedFormat( result.code )#" );
        }
        relocate( uri = "/app/profile?passwordChanged=1" );
    }

}
