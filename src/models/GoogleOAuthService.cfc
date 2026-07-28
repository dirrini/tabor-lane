component singleton {

	variables.environment = server.system.environment;
	variables.clientId = variables.environment.GOOGLE_CLIENT_ID ?: "";
	variables.clientSecret = variables.environment.GOOGLE_CLIENT_SECRET ?: "";
	variables.baseUrl = reReplace( variables.environment.APP_BASE_URL ?: "http://localhost:8090", "/$", "" );
	variables.redirectUri = variables.environment.GOOGLE_REDIRECT_URI ?: "#variables.baseUrl#/auth/google/callback";

	boolean function isConfigured(){
		return variables.clientId.len() > 0 && variables.clientSecret.len() > 0;
	}

	string function authorizationUrl( required string state ){
		return "https://accounts.google.com/o/oauth2/v2/auth"
			& "?client_id=#urlEncodedFormat( variables.clientId )#"
			& "&redirect_uri=#urlEncodedFormat( variables.redirectUri )#"
			& "&response_type=code"
			& "&scope=#urlEncodedFormat( 'openid profile email' )#"
			& "&state=#urlEncodedFormat( arguments.state )#"
			& "&prompt=select_account";
	}

	struct function exchangeCode( required string code ){
		if ( !isConfigured() ) {
			return { success = false, code = "not_configured" };
		}

		try {
			var tokenResponse = {};
			cfhttp(
				method = "POST",
				url = "https://oauth2.googleapis.com/token",
				result = "tokenResponse",
				timeout = 12
			) {
				cfhttpparam( type = "formfield", name = "code", value = arguments.code );
				cfhttpparam( type = "formfield", name = "client_id", value = variables.clientId );
				cfhttpparam( type = "formfield", name = "client_secret", value = variables.clientSecret );
				cfhttpparam( type = "formfield", name = "redirect_uri", value = variables.redirectUri );
				cfhttpparam( type = "formfield", name = "grant_type", value = "authorization_code" );
			}
			if ( val( tokenResponse.statusCode ?: 0 ) < 200 || val( tokenResponse.statusCode ?: 0 ) >= 300 ) {
				return { success = false, code = "token_exchange_failed" };
			}

			var tokenPayload = deserializeJSON( tokenResponse.fileContent ?: "{}" );
			if ( !( tokenPayload.access_token ?: "" ).len() ) {
				return { success = false, code = "missing_access_token" };
			}

			var profileResponse = {};
			cfhttp(
				method = "GET",
				url = "https://openidconnect.googleapis.com/v1/userinfo",
				result = "profileResponse",
				timeout = 12
			) {
				cfhttpparam(
					type = "header",
					name = "Authorization",
					value = "Bearer #tokenPayload.access_token#"
				);
			}
			if ( val( profileResponse.statusCode ?: 0 ) < 200 || val( profileResponse.statusCode ?: 0 ) >= 300 ) {
				return { success = false, code = "profile_failed" };
			}

			var profile = deserializeJSON( profileResponse.fileContent ?: "{}" );
			var verified = isBoolean( profile.email_verified ?: false )
				? profile.email_verified
				: lCase( profile.email_verified ?: "" ) == "true";
			if (
				!( profile.sub ?: "" ).len()
				|| !( profile.email ?: "" ).len()
				|| !verified
			) {
				return { success = false, code = "unverified_email" };
			}

			return {
				success = true,
				profile = {
					subject = profile.sub,
					email = lCase( trim( profile.email ) ),
					displayName = trim( profile.name ?: profile.email ),
					picture = profile.picture ?: ""
				}
			};
		} catch ( any exception ) {
			writeLog(
				file = "application",
				type = "error",
				text = "Google OAuth request failed: #exception.message#"
			);
			return { success = false, code = "provider_unavailable" };
		}
	}

}
