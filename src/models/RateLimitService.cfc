component singleton {

	variables.environment = server.system.environment;
	variables.restUrl = reReplace( variables.environment.UPSTASH_REDIS_REST_URL ?: "", "/$", "" );
	variables.restToken = variables.environment.UPSTASH_REDIS_REST_TOKEN ?: "";

	boolean function allow(
		required string key,
		required numeric limit,
		required numeric windowSeconds
	){
		if ( !variables.restUrl.len() || !variables.restToken.len() ) {
			return true;
		}

		try {
			var redisKey = urlEncodedFormat( "tabor-lane:rate:#arguments.key#" );
			var response = {};
			cfhttp(
				method = "POST",
				url = "#variables.restUrl#/incr/#redisKey#",
				result = "response",
				timeout = 4
			) {
				cfhttpparam( type = "header", name = "Authorization", value = "Bearer #variables.restToken#" );
			}
			var result = deserializeJSON( response.fileContent ?: "{}" );
			var count = val( result.result ?: 0 );
			if ( count == 1 ) {
				cfhttp(
					method = "POST",
					url = "#variables.restUrl#/expire/#redisKey#/#arguments.windowSeconds#",
					timeout = 4
				) {
					cfhttpparam( type = "header", name = "Authorization", value = "Bearer #variables.restToken#" );
				}
			}
			return count > 0 && count <= arguments.limit;
		} catch ( any exception ) {
			writeLog(
				file = "application",
				type = "warning",
				text = "Rate limiter unavailable; allowing request: #exception.message#"
			);
			return true;
		}
	}

}
