component singleton {

    variables.environment = server.system.environment;
    variables.endpoint = reReplace( variables.environment.STORAGE_ENDPOINT ?: "http://minio:9000", "/$", "" );
    variables.publicEndpoint = reReplace( variables.environment.STORAGE_PUBLIC_ENDPOINT ?: variables.endpoint, "/$", "" );
    variables.region = variables.environment.STORAGE_REGION ?: "auto";
    variables.accessKey = variables.environment.STORAGE_ACCESS_KEY ?: "";
    variables.secretKey = variables.environment.STORAGE_SECRET_KEY ?: "";
    variables.bucket = variables.environment.STORAGE_BUCKET ?: "tabor-lane-attachments";

    string function presign(
        required string method,
        required string objectKey,
        numeric expiresIn = 300
    ){
        return presignAtEndpoint(
            arguments.method,
            arguments.objectKey,
            arguments.expiresIn,
            variables.publicEndpoint
        );
    }

    private string function presignAtEndpoint(
        required string method,
        required string objectKey,
        required numeric expiresIn,
        required string endpoint
    ){
        var nowUtc = dateConvert( "local2utc", now() );
        var amzDate = dateTimeFormat( nowUtc, "yyyymmdd'T'HHnnss'Z'" );
        var dateStamp = dateFormat( nowUtc, "yyyymmdd" );
        var scope = "#dateStamp#/#variables.region#/s3/aws4_request";
        var endpointUri = createObject( "java", "java.net.URI" ).init( arguments.endpoint );
        var host = endpointUri.getHost();
        if ( endpointUri.getPort() > 0 ) host &= ":#endpointUri.getPort()#";
        var canonicalUri = "/#awsEncode( variables.bucket )#/#encodePath( arguments.objectKey )#";
        var query = [
            [ "X-Amz-Algorithm", "AWS4-HMAC-SHA256" ],
            [ "X-Amz-Credential", "#variables.accessKey#/#scope#" ],
            [ "X-Amz-Date", amzDate ],
            [ "X-Amz-Expires", toString( min( max( arguments.expiresIn, 1 ), 604800 ) ) ],
            [ "X-Amz-SignedHeaders", "host" ]
        ];
        var canonicalQuery = query.map( function( item ){
            return awsEncode( item[ 1 ] ) & "=" & awsEncode( item[ 2 ] );
        } ).toList( "&" );
        var canonicalRequest = uCase( arguments.method ) & chr( 10 )
            & canonicalUri & chr( 10 )
            & canonicalQuery & chr( 10 )
            & "host:#host#" & chr( 10 ) & chr( 10 )
            & "host" & chr( 10 )
            & "UNSIGNED-PAYLOAD";
        var stringToSign = "AWS4-HMAC-SHA256" & chr( 10 )
            & amzDate & chr( 10 )
            & scope & chr( 10 )
            & lCase( hash( canonicalRequest, "SHA-256" ) );
        var signingKey = hmacBinary(
            "aws4_request",
            hmacBinary(
                "s3",
                hmacBinary(
                    variables.region,
                    hmacBinary( dateStamp, charsetDecode( "AWS4#variables.secretKey#", "utf-8" ) )
                )
            )
        );
        var signature = lCase( hmac( stringToSign, signingKey, "HmacSHA256", "utf-8" ) );
        return arguments.endpoint & canonicalUri & "?" & canonicalQuery & "&X-Amz-Signature=" & signature;
    }

    struct function inspect( required string objectKey ){
        var response = {};
        var signedUrl=presignAtEndpoint(
            "HEAD",arguments.objectKey,60,variables.endpoint
        );
        cfhttp( method="HEAD", url=signedUrl, result="response", timeout=15 );
        return {
            success = left( response.statusCode ?: "", 1 ) == "2",
            statusCode = response.statusCode ?: "",
            size = val( response.responseHeader[ "Content-Length" ] ?: 0 ),
            contentType = response.responseHeader[ "Content-Type" ] ?: "application/octet-stream"
        };
    }

    struct function readObject(
        required string objectKey,
        numeric maxBytes = 1048576
    ){
        var response = {};
        var signedUrl = presignAtEndpoint(
            "GET",arguments.objectKey,60,variables.endpoint
        );
        var byteLimit = max( 1, int( arguments.maxBytes ) );
        cfhttp(
            method="GET",
            url=signedUrl,
            result="response",
            timeout=15,
            getAsBinary="yes"
        ){
            // Request one byte beyond the limit so oversized objects are
            // detected without downloading their full contents.
            cfhttpparam( type="header", name="Range", value="bytes=0-#byteLimit#" );
        }
        var hasBinaryContent = isBinary( response.fileContent ?: "" );
        var responseBytes = hasBinaryContent
            ? createObject( "java", "java.lang.reflect.Array" ).getLength( response.fileContent )
            : 0;
        var tooLarge = responseBytes > byteLimit;
        var success = left( response.statusCode ?: "", 1 ) == "2"
            && hasBinaryContent
            && !tooLarge;
        var result = {
            success = success,
            statusCode = response.statusCode ?: "",
            contentType = response.responseHeader[ "Content-Type" ] ?: "application/octet-stream",
            size = responseBytes,
            tooLarge = tooLarge
        };
        if ( success ) result.data = response.fileContent;
        return result;
    }

    struct function writeObject(
        required string objectKey,
        required binary data,
        string contentType = "application/octet-stream"
    ){
        var signedUrl = presignAtEndpoint(
            "PUT",arguments.objectKey,60,variables.endpoint
        );
        var connection = "";
        var output = "";
        var statusCode = 0;
        var errorMessage = "";
        try {
            connection = createObject( "java", "java.net.URL" )
                .init( signedUrl )
                .openConnection();
            connection.setConnectTimeout( 15000 );
            connection.setReadTimeout( 15000 );
            connection.setDoOutput( true );
            connection.setRequestMethod( "PUT" );
            connection.setRequestProperty( "Content-Type", arguments.contentType );
            var byteLength = createObject(
                "java",
                "java.lang.reflect.Array"
            ).getLength( arguments.data );
            connection.setFixedLengthStreamingMode( javacast( "int", byteLength ) );
            output = connection.getOutputStream();
            output.write( arguments.data, 0, byteLength );
            output.flush();
            statusCode = connection.getResponseCode();
        } catch ( any exception ) {
            statusCode = 0;
            errorMessage = exception.message & " " & ( exception.detail ?: "" );
        } finally {
            if ( isObject( output ) ) output.close();
            if ( isObject( connection ) ) connection.disconnect();
        }
        var result = {
            success = statusCode >= 200 && statusCode < 300,
            statusCode = statusCode
        };
        if ( errorMessage.len() ) result.error = errorMessage;
        return result;
    }

    boolean function delete( required string objectKey ){
        var response = {};
        var signedUrl=presignAtEndpoint(
            "DELETE",arguments.objectKey,60,variables.endpoint
        );
        cfhttp( method="DELETE", url=signedUrl, result="response", timeout=15 );
        return left( response.statusCode ?: "", 1 ) == "2";
    }

    private binary function hmacBinary( required string message, required any key ){
        return binaryDecode( hmac( arguments.message, arguments.key, "HmacSHA256", "utf-8" ), "hex" );
    }

    private string function encodePath( required string path ){
        return arguments.path.listToArray( "/" ).map( function( segment ){
            return awsEncode( segment );
        } ).toList( "/" );
    }

    private string function awsEncode( required string value ){
        var encoded = replace( urlEncodedFormat( arguments.value ), "+", "%20", "all" );
        encoded = replaceNoCase( encoded, "%2D", "-", "all" );
        encoded = replaceNoCase( encoded, "%2E", ".", "all" );
        encoded = replaceNoCase( encoded, "%5F", "_", "all" );
        encoded = replaceNoCase( encoded, "%7E", "~", "all" );
        return replace( encoded, "*", "%2A", "all" );
    }

}
