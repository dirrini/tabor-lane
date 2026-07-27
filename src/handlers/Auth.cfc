component {

    property name="authService" inject="AuthService";

    this.allowedMethods = {
        login = "GET",
        signup = "GET",
        authenticate = "POST",
        register = "POST",
        logout = "POST"
    };

    function login( event, rc, prc ) {
        redirectAuthenticated();
        prc.page = "login";
        prc.pageTitle = $r( "auth.login.title" );
        prc.errors = [];
        prc.formData = { email = "" };
        prc.csrfToken = csrfGenerateToken( "login" );
        event.setView( "auth/login" );
    }

    function signup( event, rc, prc ) {
        redirectAuthenticated();
        prc.page = "signup";
        prc.pageTitle = $r( "auth.signup.title" );
        prc.errors = [];
        prc.formData = { displayName = "", email = "", workspaceName = "" };
        prc.csrfToken = csrfGenerateToken( "signup" );
        event.setView( "auth/signup" );
    }

    function authenticate( event, rc, prc ) {
        redirectAuthenticated();
        prc.page = "login";
        prc.pageTitle = $r( "auth.login.title" );
        prc.errors = [];
        prc.formData = { email = trim( rc.email ?: "" ) };

        if ( !csrfVerifyToken( rc.csrfToken ?: "", "login" ) ) {
            prc.errors.append( $r( "auth.error.expired" ) );
        } else if ( !prc.formData.email.len() || !( rc.password ?: "" ).len() ) {
            prc.errors.append( $r( "auth.error.required" ) );
        } else {
            var result = authService.authenticate( prc.formData.email, rc.password );
            if ( result.success ) {
                establishSession( result.user );
                setFWLocale( result.user.locale );
                relocate( uri = "/app" );
            }
            prc.errors.append( $r( "auth.error.invalid" ) );
        }

        prc.csrfToken = csrfGenerateToken( "login", true );
        event.setView( "auth/login" );
    }

    function register( event, rc, prc ) {
        redirectAuthenticated();
        prc.page = "signup";
        prc.pageTitle = $r( "auth.signup.title" );
        prc.errors = [];
        prc.formData = {
            displayName = trim( rc.displayName ?: "" ),
            email = trim( rc.email ?: "" ),
            workspaceName = trim( rc.workspaceName ?: "" )
        };
        var password = rc.password ?: "";

        if ( !csrfVerifyToken( rc.csrfToken ?: "", "signup" ) ) {
            prc.errors.append( $r( "auth.error.expired" ) );
        } else {
            if ( !prc.formData.displayName.len() || !prc.formData.email.len() || !prc.formData.workspaceName.len() || !password.len() ) {
                prc.errors.append( $r( "auth.error.required" ) );
            }
            if ( prc.formData.email.len() && !isValid( "email", prc.formData.email ) ) {
                prc.errors.append( $r( "auth.error.email" ) );
            }
            if ( password.len() && password.len() < 10 ) {
                prc.errors.append( $r( "auth.error.password" ) );
            }
        }

        if ( !prc.errors.len() ) {
            try {
                var result = authService.register(
                    displayName = prc.formData.displayName,
                    email = prc.formData.email,
                    password = password,
                    workspaceName = prc.formData.workspaceName,
                    locale = getFWLocale()
                );
                if ( result.success ) {
                    establishSession( result.user );
                    relocate( uri = "/app" );
                }
                prc.errors.append( $r( "auth.error.exists" ) );
            } catch ( database exception ) {
                writeLog(
                    file = "application",
                    type = "error",
                    text = "Registration transaction failed: #exception.message# #exception.detail#"
                );
                prc.errors.append( $r( "auth.error.unavailable" ) );
            }
        }

        prc.csrfToken = csrfGenerateToken( "signup", true );
        event.setView( "auth/signup" );
    }

    function logout( event, rc, prc ) {
        if ( csrfVerifyToken( rc.csrfToken ?: "", "logout" ) ) {
            sessionInvalidate();
        }
        relocate( uri = "/" );
    }

    private void function establishSession( required struct user ) {
        sessionRotate();
        session.auth = duplicate( arguments.user );
        session.authenticatedAt = now();
    }

    private void function redirectAuthenticated() {
        if ( structKeyExists( session, "auth" ) ) {
            relocate( uri = "/app" );
        }
    }

}
