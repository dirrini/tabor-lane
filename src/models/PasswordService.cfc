component singleton {

	variables.algorithm = "PBKDF2WithHmacSHA256";
	variables.iterations = 210000;
	variables.keyLength = 256;

	string function hashPassword( required string password ){
		var salt = binaryDecode( repeatString( "00", 16 ), "hex" );
		createObject( "java", "java.security.SecureRandom" ).init().nextBytes( salt );
		var derivedKey = deriveKey( arguments.password, salt, variables.iterations );

		return "pbkdf2_sha256$#variables.iterations#$#toBase64( salt )#$#toBase64( derivedKey )#";
	}

	boolean function verifyPassword( required string password, required string storedHash ){
		var parts = listToArray( arguments.storedHash, "$", true );
		if ( parts.len() != 4 || parts[ 1 ] != "pbkdf2_sha256" || !isNumeric( parts[ 2 ] ) ) {
			return false;
		}

		try {
			var salt = toBinary( parts[ 3 ] );
			var expected = toBinary( parts[ 4 ] );
			var actual = deriveKey( arguments.password, salt, val( parts[ 2 ] ) );
			return createObject( "java", "java.security.MessageDigest" ).isEqual( expected, actual );
		} catch ( any ignored ) {
			return false;
		}
	}

	private any function deriveKey(
		required string password,
		required any salt,
		required numeric iterations
	){
		var passwordChars = javacast( "string", arguments.password ).toCharArray();
		var spec = createObject( "java", "javax.crypto.spec.PBEKeySpec" ).init(
			passwordChars,
			arguments.salt,
			javacast( "int", arguments.iterations ),
			javacast( "int", variables.keyLength )
		);
		var factory = createObject( "java", "javax.crypto.SecretKeyFactory" ).getInstance( variables.algorithm );

		try {
			return factory.generateSecret( spec ).getEncoded();
		} finally {
			spec.clearPassword();
		}
	}

}
