component {

    property name="stripeBillingService" inject="StripeBillingService";
    property name="authService" inject="AuthService";
    property name="workspaceViewService" inject="WorkspaceViewService";

    this.allowedMethods = {
        index = "GET",
        status = "GET",
        checkout = "POST",
        portal = "POST",
        webhook = "POST"
    };

    function preHandler( event, rc, prc, action, eventArguments ) {
        if ( arguments.action == "webhook" ) {
            return;
        }
        if ( !structKeyExists( session, "auth" ) ) {
            relocate( uri = "/login" );
        }
        session.auth.emailVerified = authService.isEmailVerified( session.auth.id );
        if ( !session.auth.emailVerified ) {
            relocate( uri = "/check-email" );
        }
        prc.auth = session.auth;
    }

    function index( event, rc, prc ) {
        prc.page = "billing";
        prc.pageTitle = $r( "billing.title" );
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
        prc.billingCsrfToken = csrfGenerateToken( "billing" );
        prc.billingPortalCsrfToken = csrfGenerateToken( "billing-portal" );
        prc.logoutCsrfToken = csrfGenerateToken( "logout" );
        prc.checkoutNotice = rc.checkout ?: "";
        prc.error = rc.error ?: "";
        workspaceViewService.render( event, prc, "app/billing" );
    }

    function checkout( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "billing" ) ) {
            relocate( uri = "/app/billing?error=expired" );
        }
        var result = stripeBillingService.createCheckout(
            userId = prc.auth.id,
            workspaceId = prc.auth.workspaceId,
            email = prc.auth.email,
            interval = rc.interval ?: "monthly"
        );
        if ( result.success ) {
            relocate( uri = result.url );
        }
        relocate( uri = "/app/billing?error=#urlEncodedFormat( result.code )#" );
    }

    function status( event, rc, prc ) {
        var billing = stripeBillingService.getBilling( prc.auth.id, prc.auth.workspaceId );
        if (
            billing.plan == "premium"
            && billing.subscriptionId.len()
            && !isDate( billing.currentPeriodEnd )
        ) {
            stripeBillingService.reconcileBilling( prc.auth.id, prc.auth.workspaceId );
            billing = stripeBillingService.getBilling( prc.auth.id, prc.auth.workspaceId );
        }
        event.renderData(
            type = "json",
            data = {
                "plan" = billing.plan ?: "free",
                "status" = billing.status ?: "none"
            }
        );
    }

    function portal( event, rc, prc ) {
        if ( !csrfVerifyToken( rc.csrfToken ?: "", "billing-portal" ) ) {
            relocate( uri = "/app/profile?error=portal_expired" );
        }
        var result = stripeBillingService.createPortal( prc.auth.id, prc.auth.workspaceId );
        if ( result.success ) {
            relocate( uri = result.url );
        }
        relocate( uri = "/app/profile?error=portal_#urlEncodedFormat( result.code )#" );
    }

    function webhook( event, rc, prc ) {
        var requestData = getHttpRequestData();
        var signature = requestData.headers[ "Stripe-Signature" ] ?: "";
        var result = stripeBillingService.processWebhook(
            payload = toString( requestData.content ?: "" ),
            signature = signature
        );
        event.renderData(
            type = "json",
            data = { received = result.success },
            statusCode = result.success ? 200 : 400
        );
    }

}
