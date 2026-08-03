component singleton {

	variables.environment = server.system.environment;
	variables.appEnvironment = lCase( trim( variables.environment.APP_ENV ?: "development" ) );

	struct function validate( required string url, boolean forDelivery = false ){
		var candidate = trim( arguments.url );
		if ( !candidate.len() || candidate.len() > 2048 ) {
			return denied( "invalid_url", candidate );
		}

		try {
			var uri = createObject( "java", "java.net.URI" ).init( candidate );
			var scheme = lCase( uri.getScheme() ?: "" );
			var host = lCase( uri.getHost() ?: "" );
			var port = val( uri.getPort() );
			var userInfo = uri.getUserInfo() ?: "";
			var fragment = uri.getFragment() ?: "";
			if (
				!host.len()
				|| !scheme.len()
				|| userInfo.len()
				|| fragment.len()
				|| ( port != -1 && ( port < 1 || port > 65535 ) )
			) return denied( "invalid_url", candidate );

			if ( variables.appEnvironment == "production" ) {
				if ( scheme != "https" ) return denied( "https_required", candidate );
				if ( isLocalHostname( host ) ) return denied( "private_destination", candidate );
				var resolved = [];
				try {
					resolved = createObject( "java", "java.net.InetAddress" )
						.getAllByName( host );
				} catch ( any dnsException ) {
					return denied( "dns_failed", candidate );
				}
				var addresses = [];
				for ( var address in resolved ) {
					if ( isForbiddenAddress( address ) ) {
						return denied( "private_destination", candidate );
					}
					addresses.append( address.getHostAddress() );
				}
				if ( !addresses.len() ) return denied( "dns_failed", candidate );
				return allowed( candidate, scheme, host, port, addresses );
			}

			if ( !listFindNoCase( "http,https", scheme ) ) {
				return denied( "invalid_scheme", candidate );
			}
			return allowed( candidate, scheme, host, port, [] );
		} catch ( any exception ) {
			return denied( "invalid_url", candidate );
		}
	}

	boolean function isAllowed( required string url, boolean forDelivery = false ){
		return validate( argumentCollection=arguments ).allowed;
	}

	private struct function allowed(
		required string url,
		required string scheme,
		required string host,
		required numeric port,
		required array addresses
	){
		return {
			success=true,
			allowed=true,
			code="ok",
			url=arguments.url,
			scheme=arguments.scheme,
			host=arguments.host,
			port=arguments.port,
			addresses=arguments.addresses
		};
	}

	private struct function denied( required string code, required string url ){
		return {
			success=false,
			allowed=false,
			code=arguments.code,
			url=arguments.url,
			addresses=[]
		};
	}

	private boolean function isLocalHostname( required string host ){
		return arguments.host == "localhost"
			|| arguments.host == "localhost.localdomain"
			|| right( arguments.host, 10 ) == ".localhost"
			|| right( arguments.host, 6 ) == ".local"
			|| right( arguments.host, 9 ) == ".internal";
	}

	private boolean function isForbiddenAddress( required any address ){
		if (
			arguments.address.isAnyLocalAddress()
			|| arguments.address.isLoopbackAddress()
			|| arguments.address.isLinkLocalAddress()
			|| arguments.address.isSiteLocalAddress()
			|| arguments.address.isMulticastAddress()
		) return true;

		var bytes = arguments.address.getAddress();
		var length = createObject( "java", "java.lang.reflect.Array" ).getLength( bytes );
		if ( length == 4 ) return forbiddenIpv4( bytes );
		if ( length != 16 ) return true;

		var first = unsignedByte( bytes[ 1 ] );
		var second = unsignedByte( bytes[ 2 ] );
		// Unique local fc00::/7, link-local fe80::/10 and multicast ff00::/8.
		if (
			bitAnd( first, 254 ) == 252
			|| ( first == 254 && bitAnd( second, 192 ) == 128 )
			|| first == 255
		) return true;

		// IPv4-mapped IPv6 addresses must be evaluated with the IPv4 policy.
		var mapped = true;
		for ( var index=1; index<=10; index++ ) {
			if ( unsignedByte( bytes[ index ] ) != 0 ) {
				mapped = false;
				break;
			}
		}
		if (
			mapped
			&& unsignedByte( bytes[ 11 ] ) == 255
			&& unsignedByte( bytes[ 12 ] ) == 255
		) {
			return forbiddenIpv4Octets(
				unsignedByte( bytes[ 13 ] ),
				unsignedByte( bytes[ 14 ] )
			);
		}
		return false;
	}

	private boolean function forbiddenIpv4( required any bytes ){
		var first = unsignedByte( arguments.bytes[ 1 ] );
		var second = unsignedByte( arguments.bytes[ 2 ] );
		return forbiddenIpv4Octets( first, second );
	}

	private boolean function forbiddenIpv4Octets(
		required numeric first,
		required numeric second
	){
		return arguments.first == 0
			|| arguments.first == 10
			|| arguments.first == 127
			|| (
				arguments.first == 100
				&& arguments.second >= 64 && arguments.second <= 127
			)
			|| ( arguments.first == 169 && arguments.second == 254 )
			|| (
				arguments.first == 172
				&& arguments.second >= 16 && arguments.second <= 31
			)
			|| ( arguments.first == 192 && arguments.second == 168 )
			|| arguments.first >= 224;
	}

	private numeric function unsignedByte( required any value ){
		var number = javacast( "int", arguments.value );
		return number < 0 ? number + 256 : number;
	}

}
