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
        var nowUtc = dateConvert( "local2utc", now() );
        var amzDate = dateTimeFormat( nowUtc, "yyyymmdd'T'HHnnss'Z'" );
        var dateStamp = dateFormat( nowUtc, "yyyymmdd" );
        var scope = "#dateStamp#/#variables.region#/s3/aws4_request";
        var endpointUri = createObject( "java", "java.net.URI" ).init( variables.publicEndpoint );
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
        return variables.publicEndpoint & canonicalUri & "?" & canonicalQuery & "&X-Amz-Signature=" & signature;
    }

    struct function inspect( required string objectKey ){
        var response = {};
        var signedUrl=presign( "HEAD", arguments.objectKey );
        cfhttp( method="HEAD", url=internalUrl(signedUrl), result="response", timeout=15 ){
            cfhttpparam(type="header",name="Host",value=publicHost());
        }
        return {
            success = left( response.statusCode ?: "", 1 ) == "2",
            statusCode = response.statusCode ?: "",
            size = val( response.responseHeader[ "Content-Length" ] ?: 0 ),
            contentType = response.responseHeader[ "Content-Type" ] ?: "application/octet-stream"
        };
    }

    boolean function delete( required string objectKey ){
        var response = {};
        var signedUrl=presign( "DELETE", arguments.objectKey );
        cfhttp( method="DELETE", url=internalUrl(signedUrl), result="response", timeout=15 ){
            cfhttpparam(type="header",name="Host",value=publicHost());
        }
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

    private string function internalUrl(required string signedUrl){
        return variables.endpoint & removeChars(arguments.signedUrl,1,variables.publicEndpoint.len());
    }

    private string function publicHost(){
        var uri=createObject("java","java.net.URI").init(variables.publicEndpoint);
        return uri.getPort()>0?"#uri.getHost()#:#uri.getPort()#":uri.getHost();
    }
}
