component {

    property name="authService" inject="AuthService";
    property name="workspaceService" inject="WorkspaceService";
    property name="notificationService" inject="NotificationService";
    property name="rateLimitService" inject="RateLimitService";

    this.allowedMethods = {
        login = "GET",
        signup = "GET",
        authenticate = "POST",
        register = "POST",
        checkEmail = "GET",
        verifyEmail = "GET",
        resendVerification = "POST",
        forgotPassword = "GET",
        requestPasswordReset = "POST",
        resetPassword = "GET",
        updatePassword = "POST",
        logout = "POST"
    };

    function login( event, rc, prc ) {
        redirectAuthenticated();
        prc.page = "login";
        prc.pageTitle = $r( "auth.login.title" );
        prc.errors = [];
        prc.formData = {
            email = "",
            invitationToken = trim( rc.invitationToken ?: "" )
        };
        if ( prc.formData.invitationToken.len() ) {
            var invitation = workspaceService.inspectInvitation( prc.formData.invitationToken );
            if ( invitation.found ) {
                prc.formData.email = invitation.email;
            }
        }
        prc.csrfToken = csrfGenerateToken( "login" );
        event.setView( "auth/login" );
    }

    function signup( event, rc, prc ) {
        redirectAuthenticated();
        prc.page = "signup";
        prc.pageTitle = $r( "auth.signup.title" );
        prc.errors = [];
        prc.formData = {
            displayName = "",
            email = "",
            workspaceName = "",
            invitationToken = trim( rc.invitationToken ?: "" )
        };
        prc.invitation = { found = false };
        if ( prc.formData.invitationToken.len() ) {
            prc.invitation = workspaceService.inspectInvitation( prc.formData.invitationToken );
            if ( prc.invitation.found ) {
                prc.formData.email = prc.invitation.email;
                prc.formData.workspaceName = prc.invitation.workspaceName;
            }
        }
        prc.csrfToken = csrfGenerateToken( "signup" );
        event.setView( "auth/signup" );
    }

    function authenticate( event, rc, prc ) {
        redirectAuthenticated();
        prc.page = "login";
        prc.pageTitle = $r( "auth.login.title" );
        prc.errors = [];
        prc.formData = {
            email = trim( rc.email ?: "" ),
            invitationToken = trim( rc.invitationToken ?: "" )
        };

        if ( !csrfVerifyToken( rc.csrfToken ?: "", "login" ) ) {
            prc.errors.append( $r( "auth.error.expired" ) );
        } else if ( !rateLimitService.allow( requestKey( "login", prc.formData.email ), 10, 900 ) ) {
            prc.errors.append( $r( "auth.error.rateLimited" ) );
        } else if ( !prc.formData.email.len() || !( rc.password ?: "" ).len() ) {
            prc.errors.append( $r( "auth.error.required" ) );
        } else {
            var result = authService.authenticate( prc.formData.email, rc.password );
            if ( result.success ) {
                if ( prc.formData.invitationToken.len() ) {
                    var acceptance = workspaceService.acceptInvitation(
                        token = prc.formData.invitationToken,
                        userId = result.user.id,
                        userEmail = result.user.email
                    );
                    if ( acceptance.success ) {
                        result.user.workspaceId = acceptance.workspaceId;
                        result.user.workspaceName = acceptance.workspaceName;
                        result.user.role = acceptance.role;
                    }
                }
                establishSession( result.user );
                setFWLocale( result.user.locale );
                relocate( uri = result.user.emailVerified ? "/app" : "/check-email" );
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
            workspaceName = trim( rc.workspaceName ?: "" ),
            invitationToken = trim( rc.invitationToken ?: "" )
        };
        prc.invitation = prc.formData.invitationToken.len()
            ? workspaceService.inspectInvitation( prc.formData.invitationToken )
            : { found = false };
        var password = rc.password ?: "";

        if ( !csrfVerifyToken( rc.csrfToken ?: "", "signup" ) ) {
            prc.errors.append( $r( "auth.error.expired" ) );
        } else {
            if (
                !prc.formData.displayName.len()
                || !prc.formData.email.len()
                || ( !prc.invitation.found && !prc.formData.workspaceName.len() )
                || !password.len()
            ) {
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
                    locale = getFWLocale(),
                    invitationToken = prc.formData.invitationToken
                );
                if ( result.success ) {
                    establishSession( result.user );
                    notificationService.sendEmailVerification( result.user, result.verificationToken );
                    exposeDevelopmentToken( "verification", result.verificationToken );
                    relocate( uri = "/check-email" );
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

    function checkEmail( event, rc, prc ) {
        if ( !structKeyExists( session, "auth" ) ) {
            relocate( uri = "/login" );
        }
        if ( authService.isEmailVerified( session.auth.id ) ) {
            session.auth.emailVerified = true;
            relocate( uri = "/app" );
        }
        prc.page = "check-email";
        prc.pageTitle = $r( "auth.verify.title" );
        prc.auth = session.auth;
        prc.csrfToken = csrfGenerateToken( "resend-verification" );
        prc.developmentToken = developmentToken( "verification" );
        event.setView( "auth/checkEmail" );
    }

    function verifyEmail( event, rc, prc ) {
        var result = authService.verifyEmail( rc.token ?: "" );
        prc.page = "verified";
        prc.success = result.success;
        prc.pageTitle = result.success ? $r( "auth.verified.title" ) : $r( "auth.verify.invalidTitle" );
        if ( result.success && structKeyExists( session, "auth" ) && session.auth.id == result.userId ) {
            session.auth.emailVerified = true;
            structDelete( session, "developmentTokens" );
        }
        event.setView( "auth/verified" );
    }

    function resendVerification( event, rc, prc ) {
        if ( !structKeyExists( session, "auth" ) ) {
            relocate( uri = "/login" );
        }
        if (
            csrfVerifyToken( rc.csrfToken ?: "", "resend-verification" )
            && rateLimitService.allow( requestKey( "verify", session.auth.email ), 3, 3600 )
        ) {
            var result = authService.createVerificationToken( session.auth.id );
            if ( result.success ) {
                notificationService.sendEmailVerification( session.auth, result.token );
                exposeDevelopmentToken( "verification", result.token );
            }
        }
        relocate( uri = "/check-email?sent=1" );
    }

    function forgotPassword( event, rc, prc ) {
        prc.page = "forgot-password";
        prc.pageTitle = $r( "auth.forgot.title" );
        prc.errors = [];
        prc.sent = false;
        prc.formData = { email = "" };
        prc.csrfToken = csrfGenerateToken( "forgot-password" );
        event.setView( "auth/forgotPassword" );
    }

    function requestPasswordReset( event, rc, prc ) {
        prc.page = "forgot-password";
        prc.pageTitle = $r( "auth.forgot.title" );
        prc.errors = [];
        prc.sent = false;
        prc.formData = { email = trim( rc.email ?: "" ) };

        if ( !csrfVerifyToken( rc.csrfToken ?: "", "forgot-password" ) ) {
            prc.errors.append( $r( "auth.error.expired" ) );
        } else if ( !rateLimitService.allow( requestKey( "password", prc.formData.email ), 3, 3600 ) ) {
            prc.errors.append( $r( "auth.error.rateLimited" ) );
        } else if ( !isValid( "email", prc.formData.email ) ) {
            prc.errors.append( $r( "auth.error.email" ) );
        } else {
            var result = authService.requestPasswordReset( prc.formData.email );
            if ( result.found ) {
                notificationService.sendPasswordReset( result.user, result.token );
                exposeDevelopmentToken( "passwordReset", result.token );
            }
            prc.sent = true;
        }
        prc.developmentToken = developmentToken( "passwordReset" );
        prc.csrfToken = csrfGenerateToken( "forgot-password", true );
        event.setView( "auth/forgotPassword" );
    }

    function resetPassword( event, rc, prc ) {
        prc.page = "reset-password";
        prc.pageTitle = $r( "auth.reset.title" );
        prc.errors = [];
        prc.token = rc.token ?: "";
        prc.csrfToken = csrfGenerateToken( "reset-password" );
        event.setView( "auth/resetPassword" );
    }

    function updatePassword( event, rc, prc ) {
        prc.page = "reset-password";
        prc.pageTitle = $r( "auth.reset.title" );
        prc.errors = [];
        prc.token = rc.token ?: "";
        var password = rc.password ?: "";

        if ( !csrfVerifyToken( rc.csrfToken ?: "", "reset-password" ) ) {
            prc.errors.append( $r( "auth.error.expired" ) );
        } else if ( password.len() < 10 ) {
            prc.errors.append( $r( "auth.error.password" ) );
        } else {
            var result = authService.resetPassword( prc.token, password );
            if ( result.success ) {
                structDelete( session, "developmentTokens" );
                relocate( uri = "/login?passwordReset=1" );
            }
            prc.errors.append( $r( "auth.reset.invalid" ) );
        }
        prc.csrfToken = csrfGenerateToken( "reset-password", true );
        event.setView( "auth/resetPassword" );
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
            relocate( uri = ( session.auth.emailVerified ?: false ) ? "/app" : "/check-email" );
        }
    }

    private string function requestKey( required string action, string identity = "" ) {
        var remoteAddress = cgi.remote_addr ?: "unknown";
        return "#arguments.action#:#remoteAddress#:#lCase( trim( arguments.identity ) )#";
    }

    private void function exposeDevelopmentToken( required string purpose, required string token ) {
        if ( ( server.system.environment.APP_ENV ?: "development" ) != "production" ) {
            if ( !structKeyExists( session, "developmentTokens" ) ) {
                session.developmentTokens = {};
            }
            session.developmentTokens[ arguments.purpose ] = arguments.token;
        }
    }

    private string function developmentToken( required string purpose ) {
        return ( server.system.environment.APP_ENV ?: "development" ) != "production"
            && structKeyExists( session, "developmentTokens" )
            && structKeyExists( session.developmentTokens, arguments.purpose )
                ? session.developmentTokens[ arguments.purpose ]
                : "";
    }

}
