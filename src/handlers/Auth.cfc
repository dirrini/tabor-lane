component {

    property name="authService" inject="AuthService";
    property name="workspaceService" inject="WorkspaceService";
    property name="notificationService" inject="NotificationService";
    property name="rateLimitService" inject="RateLimitService";
    property name="googleOAuthService" inject="GoogleOAuthService";

    this.allowedMethods = {
        login = "GET",
        signup = "GET",
        authenticate = "POST",
        googleStart = "GET",
        googleCallback = "GET",
        googleOnboarding = "GET",
        completeGoogleRegistration = "POST",
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
        prc.googleOAuthEnabled = googleOAuthService.isConfigured();
        if ( ( rc.oauth ?: "" ) == "failed" ) {
            prc.errors.append( $r( "auth.google.error" ) );
        }
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
        prc.googleOAuthEnabled = googleOAuthService.isConfigured();
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
        prc.googleOAuthEnabled = googleOAuthService.isConfigured();
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
        prc.googleOAuthEnabled = googleOAuthService.isConfigured();
        event.setView( "auth/signup" );
    }

    function googleStart( event, rc, prc ) {
        redirectAuthenticated();
        if ( !googleOAuthService.isConfigured() ) {
            relocate( uri = "/login?oauth=failed" );
        }
        var state = lCase( hash( createUUID() & getTickCount() & randRange( 100000, 999999 ), "SHA-256" ) );
        session.googleOAuthState = {
            value = state,
            expiresAt = dateAdd( "n", 10, now() ),
            invitationToken = trim( rc.invitationToken ?: "" )
        };
        relocate( uri = googleOAuthService.authorizationUrl( state ) );
    }

    function googleCallback( event, rc, prc ) {
        redirectAuthenticated();
        var oauthState = session.googleOAuthState ?: {};
        structDelete( session, "googleOAuthState" );
        if (
            ( rc.error ?: "" ).len()
            || !( rc.code ?: "" ).len()
            || !( rc.state ?: "" ).len()
            || !( oauthState.value ?: "" ).len()
            || !constantTimeEquals( rc.state, oauthState.value )
            || isNull( oauthState.expiresAt )
            || oauthState.expiresAt < now()
        ) {
            relocate( uri = "/login?oauth=failed" );
        }

        var providerResult = googleOAuthService.exchangeCode( rc.code );
        if ( !providerResult.success ) {
            relocate( uri = "/login?oauth=failed" );
        }
        var authResult = authService.authenticateExternal(
            provider = "google",
            subject = providerResult.profile.subject,
            email = providerResult.profile.email
        );
        if ( authResult.success ) {
            authResult.user = acceptPendingInvitation( authResult.user, oauthState.invitationToken ?: "" );
            establishSession( authResult.user );
            setFWLocale( authResult.user.locale );
            relocate( uri = "/app" );
        }
        if ( !( authResult.needsRegistration ?: false ) ) {
            relocate( uri = "/login?oauth=failed" );
        }

        session.pendingGoogleRegistration = {
            profile = providerResult.profile,
            invitationToken = oauthState.invitationToken ?: "",
            expiresAt = dateAdd( "n", 10, now() )
        };
        relocate( uri = "/auth/google/onboarding" );
    }

    function googleOnboarding( event, rc, prc ) {
        redirectAuthenticated();
        var pending = pendingGoogleRegistration();
        if ( !pending.found ) {
            relocate( uri = "/login?oauth=failed" );
        }
        prc.page = "google-onboarding";
        prc.pageTitle = $r( "auth.google.onboarding.title" );
        prc.errors = [];
        prc.profile = pending.data.profile;
        prc.invitation = ( pending.data.invitationToken ?: "" ).len()
            ? workspaceService.inspectInvitation( pending.data.invitationToken )
            : { found = false };
        prc.formData = {
            displayName = prc.profile.displayName,
            workspaceName = ""
        };
        prc.csrfToken = csrfGenerateToken( "google-onboarding" );
        event.setView( "auth/googleOnboarding" );
    }

    function completeGoogleRegistration( event, rc, prc ) {
        redirectAuthenticated();
        var pending = pendingGoogleRegistration();
        if ( !pending.found ) {
            relocate( uri = "/login?oauth=failed" );
        }
        prc.page = "google-onboarding";
        prc.pageTitle = $r( "auth.google.onboarding.title" );
        prc.errors = [];
        prc.profile = pending.data.profile;
        prc.invitation = ( pending.data.invitationToken ?: "" ).len()
            ? workspaceService.inspectInvitation( pending.data.invitationToken )
            : { found = false };
        prc.formData = {
            displayName = trim( rc.displayName ?: "" ),
            workspaceName = trim( rc.workspaceName ?: "" )
        };

        if ( !csrfVerifyToken( rc.csrfToken ?: "", "google-onboarding" ) ) {
            prc.errors.append( $r( "auth.error.expired" ) );
        } else if (
            !prc.formData.displayName.len()
            || ( !prc.invitation.found && !prc.formData.workspaceName.len() )
        ) {
            prc.errors.append( $r( "auth.error.required" ) );
        }

        if ( !prc.errors.len() ) {
            var result = authService.registerExternal(
                provider = "google",
                subject = prc.profile.subject,
                email = prc.profile.email,
                displayName = prc.formData.displayName,
                workspaceName = prc.formData.workspaceName,
                locale = getFWLocale(),
                invitationToken = pending.data.invitationToken ?: ""
            );
            if ( result.success ) {
                structDelete( session, "pendingGoogleRegistration" );
                establishSession( result.user );
                setFWLocale( result.user.locale );
                relocate( uri = "/app" );
            }
            prc.errors.append( $r( "auth.google.error" ) );
        }

        prc.csrfToken = csrfGenerateToken( "google-onboarding", true );
        event.setView( "auth/googleOnboarding" );
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

    private struct function acceptPendingInvitation( required struct user, string invitationToken = "" ) {
        if ( !trim( arguments.invitationToken ).len() ) {
            return arguments.user;
        }
        var acceptance = workspaceService.acceptInvitation(
            token = arguments.invitationToken,
            userId = arguments.user.id,
            userEmail = arguments.user.email
        );
        if ( acceptance.success ) {
            arguments.user.workspaceId = acceptance.workspaceId;
            arguments.user.workspaceName = acceptance.workspaceName;
            arguments.user.role = acceptance.role;
        }
        return arguments.user;
    }

    private struct function pendingGoogleRegistration() {
        if (
            !structKeyExists( session, "pendingGoogleRegistration" )
            || isNull( session.pendingGoogleRegistration.expiresAt )
            || session.pendingGoogleRegistration.expiresAt < now()
        ) {
            structDelete( session, "pendingGoogleRegistration" );
            return { found = false };
        }
        return { found = true, data = session.pendingGoogleRegistration };
    }

    private boolean function constantTimeEquals( required string first, required string second ) {
        if ( arguments.first.len() != arguments.second.len() ) {
            return false;
        }
        var difference = 0;
        for ( var index = 1; index <= arguments.first.len(); index++ ) {
            difference = bitOr(
                difference,
                bitXor( asc( mid( arguments.first, index, 1 ) ), asc( mid( arguments.second, index, 1 ) ) )
            );
        }
        return difference == 0;
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
