component singleton {

	string function generateToken(){
		var bytes = createObject( "java", "java.nio.ByteBuffer" ).allocate( 32 ).array();
		createObject( "java", "java.security.SecureRandom" ).init().nextBytes( bytes );
		return createObject( "java", "java.util.Base64" )
			.getUrlEncoder()
			.withoutPadding()
			.encodeToString( bytes );
	}

	string function hashToken( required string token ){
		return lCase( hash( arguments.token, "SHA-256" ) );
	}

	string function createAuthToken(
		required string userId,
		required string purpose,
		numeric lifetimeMinutes = 60
	){
		var token = generateToken();
		transaction {
			queryExecute(
				"UPDATE auth_token
				 SET consumed_at = now()
				 WHERE user_id = CAST(:userId AS UUID)
				   AND purpose = :purpose
				   AND consumed_at IS NULL",
				{ userId = arguments.userId, purpose = arguments.purpose }
			);
			queryExecute(
				"INSERT INTO auth_token (user_id, purpose, token_hash, expires_at)
				 VALUES (CAST(:userId AS UUID), :purpose, :tokenHash, :expiresAt)",
				{
					userId = arguments.userId,
					purpose = arguments.purpose,
					tokenHash = hashToken( token ),
					expiresAt = {
						value = dateAdd( "n", arguments.lifetimeMinutes, now() ),
						sqltype = "timestamp"
					}
				}
			);
		}
		return token;
	}

	struct function consumeAuthToken( required string token, required string purpose ){
		var rows = queryExecute(
			"UPDATE auth_token
			 SET consumed_at = now()
			 WHERE token_hash = :tokenHash
			   AND purpose = :purpose
			   AND consumed_at IS NULL
			   AND expires_at > now()
			 RETURNING CAST(user_id AS TEXT) AS user_id",
			{ tokenHash = hashToken( arguments.token ), purpose = arguments.purpose },
			{ returntype = "array" }
		);
		return rows.len()
			? { success = true, userId = rows[ 1 ].user_id }
			: { success = false, code = "invalid_or_expired" };
	}

}
