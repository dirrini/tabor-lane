component {

    function configure() {
        setFullRewrites( true );

        route( "/" ).to( "Home.index" );
        post( "/app/cards/:cardId/move" ).to( "App.moveCard" );
        post( "/app/cards" ).to( "App.createCard" );
        route( "/app" ).to( "App.index" );
        post( "/auth/logout" ).to( "Auth.logout" );
        post( "/auth/login" ).to( "Auth.authenticate" );
        route( "/login" ).to( "Auth.login" );
        post( "/auth/register" ).to( "Auth.register" );
        route( "/signup" ).to( "Auth.signup" );
        route( "/locale/:locale" ).to( "Locale.change" );
        route( "/health/live" ).to( "Health.live" );
        route( "/health/ready" ).to( "Health.ready" );

        route( ":handler/:action?" ).end();
    }

}
