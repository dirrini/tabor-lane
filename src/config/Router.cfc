component {

    function configure() {
        setFullRewrites( true );

        route( "/" ).to( "Home.index" );
        route( "/app" ).to( "App.index" );
        route( "/login" ).to( "Auth.login" );
        route( "/signup" ).to( "Auth.signup" );
        route( "/locale/:locale" ).to( "Locale.change" );
        route( "/health/live" ).to( "Health.live" );
        route( "/health/ready" ).to( "Health.ready" );

        route( ":handler/:action?" ).end();
    }

}
