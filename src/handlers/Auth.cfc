component {

    function login( event, rc, prc ) {
        prc.page = "login";
        prc.pageTitle = $r( "auth.login.title" );
        event.setView( "auth/login" );
    }

    function signup( event, rc, prc ) {
        prc.page = "signup";
        prc.pageTitle = $r( "auth.signup.title" );
        event.setView( "auth/signup" );
    }

}

