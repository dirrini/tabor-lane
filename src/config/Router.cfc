component {

    function configure() {
        setFullRewrites( true );

        route( "/" ).to( "Home.index" );
        post( "/stripe/webhook" ).to( "Billing.webhook" );
        post( "/app/billing/checkout" ).to( "Billing.checkout" );
        post( "/app/billing/portal" ).to( "Billing.portal" );
        route( "/app/billing/status" ).to( "Billing.status" );
        route( "/app/billing" ).to( "Billing.index" );
        post( "/app/profile/password" ).to( "Profile.changePassword" );
        post( "/app/profile/details" ).to( "Profile.update" );
        route( "/app/profile" ).to( "Profile.index" );
        post( "/app/members/invite" ).to( "App.inviteMember" );
        route( "/app/members" ).to( "App.members" );
        get( "/app/attachments/:attachmentId/download" ).to( "Attachments.download" );
        post( "/app/cards/:cardId/attachments/:attachmentId/remove" ).to( "Attachments.remove" );
        post( "/app/cards/:cardId/attachments/:attachmentId/complete" ).to( "Attachments.complete" );
        post( "/app/cards/:cardId/attachments/presign" ).to( "Attachments.presign" );
        post( "/app/cards/:cardId/comments" ).to( "App.addCardComment" );
        post( "/app/cards/:cardId/archive" ).to( "App.archiveCard" );
        post( "/app/cards/:cardId/move" ).to( "App.moveCard" );
        post( "/app/cards/:cardId" ).to( "App.updateCard" );
        get( "/app/cards/:cardId" ).to( "App.cardDetails" );
        post( "/app/cards" ).to( "App.createCard" );
        route( "/app" ).to( "App.index" );
        post( "/auth/logout" ).to( "Auth.logout" );
        post( "/auth/login" ).to( "Auth.authenticate" );
        route( "/auth/google/callback" ).to( "Auth.googleCallback" );
        post( "/auth/google/complete" ).to( "Auth.completeGoogleRegistration" );
        route( "/auth/google/onboarding" ).to( "Auth.googleOnboarding" );
        route( "/auth/google" ).to( "Auth.googleStart" );
        route( "/login" ).to( "Auth.login" );
        post( "/auth/register" ).to( "Auth.register" );
        route( "/signup" ).to( "Auth.signup" );
        post( "/auth/resend-verification" ).to( "Auth.resendVerification" );
        route( "/verify-email/:token" ).to( "Auth.verifyEmail" );
        route( "/check-email" ).to( "Auth.checkEmail" );
        post( "/auth/forgot-password" ).to( "Auth.requestPasswordReset" );
        route( "/forgot-password" ).to( "Auth.forgotPassword" );
        post( "/auth/reset-password" ).to( "Auth.updatePassword" );
        route( "/reset-password/:token" ).to( "Auth.resetPassword" );
        route( "/invite/:token" ).to( "Invitations.accept" );
        route( "/locale/:locale" ).to( "Locale.change" );
        route( "/health/live" ).to( "Health.live" );
        route( "/health/ready" ).to( "Health.ready" );

        route( ":handler/:action?" ).end();
    }

}
