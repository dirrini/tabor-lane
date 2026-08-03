component singleton {

	variables.environment = server.system.environment;
	variables.appEnvironment = lCase( trim( variables.environment.APP_ENV ?: "development" ) );
	variables.configuredKey = trim(
		variables.environment.WEBHOOK_SECRET_ENCRYPTION_KEY ?: ""
	);
	variables.keyVersion = 1;

	if ( variables.appEnvironment == "production" && !variables.configuredKey.len() ) {
		throw(
			type="WebhookCrypto.MissingEncryptionKey",
			message="WEBHOOK_SECRET_ENCRYPTION_KEY is required in production."
		);
	}

	string function generateSecret(){
		return "tlwh_" & base64UrlEncode( randomBytes( 32 ) );
	}

	struct function encryptSecret(
		required string secret,
		required string workspaceId,
		required string endpointId,
		numeric keyVersion = 1
	){
		if ( !arguments.secret.len() ) invalid( "invalid_secret" );
		if (
			!isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.endpointId )
			|| fix( arguments.keyVersion ) != variables.keyVersion
		) invalid( "invalid_context" );

		var nonce = randomBytes( 12 );
		var cipher = createObject( "java", "javax.crypto.Cipher" )
			.getInstance( "AES/GCM/NoPadding" );
		var key = createObject( "java", "javax.crypto.spec.SecretKeySpec" ).init(
			masterKey(),
			"AES"
		);
		var parameters = createObject(
			"java",
			"javax.crypto.spec.GCMParameterSpec"
		).init( javacast( "int", 128 ), nonce );
		cipher.init( javacast( "int", 1 ), key, parameters );
		cipher.updateAAD( charsetDecode( encryptionContext(
			workspaceId=arguments.workspaceId,
			endpointId=arguments.endpointId,
			keyVersion=arguments.keyVersion
		), "utf-8" ) );
		var ciphertext = cipher.doFinal( charsetDecode( arguments.secret, "utf-8" ) );

		return {
			ciphertext=base64UrlEncode( ciphertext ),
			nonce=base64UrlEncode( nonce ),
			keyVersion=variables.keyVersion,
			hint=right( arguments.secret, 8 )
		};
	}

	string function decryptSecret(
		required string ciphertext,
		required string nonce,
		required string workspaceId,
		required string endpointId,
		numeric keyVersion = 1
	){
		if (
			!arguments.ciphertext.len()
			|| !arguments.nonce.len()
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.endpointId )
			|| fix( arguments.keyVersion ) != variables.keyVersion
		) invalid( "invalid_context" );

		try {
			var decodedNonce = base64UrlDecode( arguments.nonce );
			if ( binaryLength( decodedNonce ) != 12 ) invalid( "invalid_ciphertext" );
			var cipher = createObject( "java", "javax.crypto.Cipher" )
				.getInstance( "AES/GCM/NoPadding" );
			var key = createObject( "java", "javax.crypto.spec.SecretKeySpec" ).init(
				masterKey(),
				"AES"
			);
			var parameters = createObject(
				"java",
				"javax.crypto.spec.GCMParameterSpec"
			).init( javacast( "int", 128 ), decodedNonce );
			cipher.init( javacast( "int", 2 ), key, parameters );
			cipher.updateAAD( charsetDecode( encryptionContext(
				workspaceId=arguments.workspaceId,
				endpointId=arguments.endpointId,
				keyVersion=arguments.keyVersion
			), "utf-8" ) );
			var plaintext = cipher.doFinal( base64UrlDecode( arguments.ciphertext ) );
			return charsetEncode( plaintext, "utf-8" );
		} catch ( WebhookCrypto exception ) {
			rethrow;
		} catch ( any exception ) {
			throw(
				type="WebhookCrypto.InvalidCiphertext",
				message="The webhook secret could not be decrypted.",
				detail="invalid_ciphertext"
			);
		}
	}

	string function signPayload(
		required string requestBody,
		required numeric timestamp,
		required string deliveryId,
		required string secret
	){
		if (
			arguments.timestamp <= 0
			|| !isCanonicalUuid( arguments.deliveryId )
			|| !arguments.secret.len()
		) {
			invalid( "invalid_signature_input" );
		}
		return lCase(
			hmac(
				"#fix( arguments.timestamp )#.#lCase( trim( arguments.deliveryId ) )#.#arguments.requestBody#",
				arguments.secret,
				"HmacSHA256",
				"utf-8"
			)
		);
	}

	string function buildSignatureHeader(
		required string requestBody,
		required string deliveryId,
		required string secret,
		numeric timestamp = 0
	){
		var effectiveTimestamp = arguments.timestamp > 0
			? fix( arguments.timestamp )
			: fix(
				createObject( "java", "java.lang.System" ).currentTimeMillis() / 1000
			);
		var signature = signPayload(
			requestBody=arguments.requestBody,
			timestamp=effectiveTimestamp,
			deliveryId=arguments.deliveryId,
			secret=arguments.secret
		);
		return "t=#effectiveTimestamp#,d=#lCase( trim( arguments.deliveryId ) )#,v1=#signature#";
	}

	private any function masterKey(){
		if ( variables.configuredKey.len() ) {
			try {
				var decoded = decodeConfiguredKey( variables.configuredKey );
				if ( binaryLength( decoded ) != 32 ) {
					throw( message="The decoded key was not 32 bytes." );
				}
				return decoded;
			} catch ( any exception ) {
				throw(
					type="WebhookCrypto.InvalidEncryptionKey",
					message="WEBHOOK_SECRET_ENCRYPTION_KEY must be a Base64-encoded 32-byte key."
				);
			}
		}
		if ( variables.appEnvironment != "development" ) {
			throw(
				type="WebhookCrypto.MissingEncryptionKey",
				message="WEBHOOK_SECRET_ENCRYPTION_KEY is required outside development."
			);
		}

		return createObject( "java", "java.security.MessageDigest" )
			.getInstance( "SHA-256" )
			.digest(
				charsetDecode(
					"tabor-lane-development-only-webhook-encryption-key",
					"utf-8"
				)
			);
	}

	private any function decodeConfiguredKey( required string value ){
		try {
			return createObject( "java", "java.util.Base64" )
				.getDecoder()
				.decode( arguments.value );
		} catch ( any standardBase64Exception ) {
			return createObject( "java", "java.util.Base64" )
				.getUrlDecoder()
				.decode( arguments.value );
		}
	}

	private any function randomBytes( required numeric length ){
		var bytes = createObject( "java", "java.nio.ByteBuffer" )
			.allocate( javacast( "int", arguments.length ) )
			.array();
		createObject( "java", "java.security.SecureRandom" ).init().nextBytes( bytes );
		return bytes;
	}

	private numeric function binaryLength( required any value ){
		return createObject( "java", "java.lang.reflect.Array" )
			.getLength( arguments.value );
	}

	private string function base64UrlEncode( required any value ){
		return createObject( "java", "java.util.Base64" )
			.getUrlEncoder()
			.withoutPadding()
			.encodeToString( arguments.value );
	}

	private any function base64UrlDecode( required string value ){
		return createObject( "java", "java.util.Base64" )
			.getUrlDecoder()
			.decode( arguments.value );
	}

	private string function encryptionContext(
		required string workspaceId,
		required string endpointId,
		numeric keyVersion = 1
	){
		return lCase( trim( arguments.workspaceId ) )
			& ":" & lCase( trim( arguments.endpointId ) )
			& ":" & fix( arguments.keyVersion );
	}

	private boolean function isCanonicalUuid( required string value ){
		return reFindNoCase(
			"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
			trim( arguments.value )
		) > 0;
	}

	private void function invalid( required string code ){
		throw(
			type="WebhookCrypto.InvalidInput",
			message="The webhook cryptography input was invalid.",
			detail=arguments.code
		);
	}

}
