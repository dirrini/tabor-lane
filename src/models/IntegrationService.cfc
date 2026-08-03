component singleton {

	property name="webhookCryptoService" inject="WebhookCryptoService";
	property name="webhookUrlPolicyService" inject="WebhookUrlPolicyService";

	variables.scopes = [
		"boards:read",
		"cards:read",
		"cards:create",
		"cards:update",
		"cards:move"
	];
	variables.writeScopes = [ "cards:create", "cards:update", "cards:move" ];
	variables.eventTypes = [
		"card.created",
		"card.moved",
		"card.reordered",
		"card.updated",
		"card.assigned",
		"card.archived",
		"card.blocked",
		"card.unblocked",
		"card.completed",
		"card.reopened"
	];

	struct function getDashboard(
		required string userId,
		required string workspaceId
	){
		var access = workspaceAccess( arguments.userId, arguments.workspaceId );
		if ( !access.found ) return { found=false, code="not_found" };

		var limits = planLimits( access.plan );
		var canManage = listFindNoCase( "owner,admin", access.role ) > 0;
		var result = {
			found=true,
			code="ok",
			role=access.role,
			plan=access.plan,
			canManage=canManage,
			tokenLimit=limits.tokenLimit,
			endpointLimit=limits.endpointLimit,
			activeTokenCount=0,
			activeEndpointCount=0,
			tokens=[],
			endpoints=[],
			deliveries=[],
			eventTypes=duplicate( variables.eventTypes ),
			scopes=duplicate( variables.scopes )
		};
		if ( !canManage ) return result;

		result.tokens = queryExecute(
			"SELECT CAST(token.id AS TEXT) AS id,token.name,
			        'tlk_' || token.public_id || '_...' AS token_prefix,
			        COALESCE((
			            SELECT string_agg(scope.value,',' ORDER BY scope.ordinality)
			            FROM jsonb_array_elements_text(token.scopes)
			                 WITH ORDINALITY scope(value,ordinality)
			        ),'') AS scopes_csv,
			        token.expires_at,token.last_used_at,token.revoked_at,token.created_at
			 FROM api_token token
			 WHERE token.workspace_id=CAST(:workspaceId AS UUID)
			 ORDER BY token.created_at DESC,token.id DESC
			 LIMIT 100",
			{ workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		result.endpoints = queryExecute(
			"SELECT CAST(endpoint.id AS TEXT) AS id,endpoint.name,endpoint.url,
			        COALESCE((
			            SELECT string_agg(event_type.value,',' ORDER BY event_type.ordinality)
			            FROM jsonb_array_elements_text(endpoint.event_types)
			                 WITH ORDINALITY event_type(value,ordinality)
			        ),'') AS event_types_csv,
			        endpoint.is_enabled,endpoint.secret_hint,endpoint.last_success_at,
			        endpoint.last_failure_at,endpoint.created_at
			 FROM webhook_endpoint endpoint
			 WHERE endpoint.workspace_id=CAST(:workspaceId AS UUID)
			   AND endpoint.deleted_at IS NULL
			 ORDER BY endpoint.created_at DESC,endpoint.id DESC",
			{ workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		result.deliveries = queryExecute(
			"SELECT CAST(delivery.id AS TEXT) AS id,endpoint.name AS endpoint_name,
			        delivery.event_type,delivery.attempts,delivery.last_http_status,
			        delivery.delivered_at,delivery.failed_at,delivery.available_at,
			        delivery.last_error,delivery.created_at
			 FROM webhook_delivery delivery
			 JOIN webhook_endpoint endpoint
			   ON endpoint.id=delivery.endpoint_id
			  AND endpoint.workspace_id=delivery.workspace_id
			 WHERE delivery.workspace_id=CAST(:workspaceId AS UUID)
			 ORDER BY delivery.created_at DESC,delivery.id DESC
			 LIMIT 50",
			{ workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		result.activeTokenCount = queryExecute(
			"SELECT COUNT(*) AS total
			 FROM api_token
			 WHERE workspace_id=CAST(:workspaceId AS UUID)
			   AND revoked_at IS NULL AND expires_at>now()",
			{ workspaceId=arguments.workspaceId },
			{ returntype="array" }
		)[ 1 ].total;
		result.activeEndpointCount = result.endpoints.len();
		return result;
	}

	struct function createToken(
		required string userId,
		 required string workspaceId,
		 required string name,
		 required any scopes,
		 required any expirationDays
	){
		var cleanName = trim( arguments.name );
		var days = isNumeric( arguments.expirationDays )
			? fix( arguments.expirationDays )
			: 0;
		var normalizedScopes = normalizeAllowedValues( arguments.scopes, variables.scopes );
		if ( !collectionArray( arguments.scopes ).len() ) return failure( "scope_required" );
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !cleanName.len() || cleanName.len() > 120
			|| !isNumeric( arguments.expirationDays )
			|| days != arguments.expirationDays || days < 1 || days > 365
			|| !normalizedScopes.valid
		) return failure( "invalid" );

		var publicId = lCase( binaryEncode( randomBytes( 8 ), "hex" ) );
		var rawToken = "tlk_" & publicId & "_" & base64UrlEncode( randomBytes( 32 ) );
		var outcome = failure( "forbidden" );
		try {
			transaction {
				var access = lockedWorkspaceAccess( arguments.userId, arguments.workspaceId );
				if ( !canManage( access ) ) {
					outcome = failure( "forbidden" );
				} else {
					var limits = planLimits( access.plan );
					var activeCount = queryExecute(
						"SELECT COUNT(*) AS total
						 FROM api_token
						 WHERE workspace_id=CAST(:workspaceId AS UUID)
						   AND revoked_at IS NULL AND expires_at>now()",
						{ workspaceId=arguments.workspaceId },
						{ returntype="array" }
					)[ 1 ].total;
					if ( val( activeCount ) >= limits.tokenLimit ) {
						outcome = failure( "limit_reached" );
					} else {
						var inserted = queryExecute(
							"INSERT INTO api_token(
							     workspace_id,subject_user_id,name,public_id,token_hash,scopes,expires_at
							 )
							 VALUES(
							     CAST(:workspaceId AS UUID),CAST(:userId AS UUID),:name,:publicId,
							     :tokenHash,CAST(:scopes AS JSONB),
							     now()+make_interval(days => CAST(:expirationDays AS INTEGER))
							 )
							 RETURNING CAST(id AS TEXT) AS id,expires_at",
							{
								workspaceId=arguments.workspaceId,
								userId=arguments.userId,
								name=cleanName,
								publicId=publicId,
								tokenHash=hashToken( rawToken ),
								scopes=serializeJSON( normalizedScopes.values ),
								expirationDays=days
							},
							{ returntype="array" }
						);
						outcome = {
							success=true,
							code="ok",
							id=inserted[ 1 ].id,
							name=cleanName,
							token=rawToken,
							rawToken=rawToken,
							tokenPrefix="tlk_#publicId#_...",
							expiresAt=inserted[ 1 ].expires_at
						};
					}
				}
			}
		} catch ( database exception ) {
			if ( ( exception.sqlState ?: "" ) == "23505" ) return failure( "duplicate" );
			rethrow;
		}
		return outcome;
	}

	struct function revokeToken(
		required string userId,
		required string workspaceId,
		required string tokenId
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.tokenId )
		) return failure( "not_found" );
		var rows = queryExecute(
			"UPDATE api_token token
			 SET revoked_at=COALESCE(token.revoked_at,now()),
			     revoked_by=COALESCE(token.revoked_by,CAST(:userId AS UUID))
			 FROM workspace_member actor
			 WHERE token.id=CAST(:tokenId AS UUID)
			   AND token.workspace_id=CAST(:workspaceId AS UUID)
			   AND actor.workspace_id=token.workspace_id
			   AND actor.user_id=CAST(:userId AS UUID)
			   AND actor.role IN ('owner','admin')
			 RETURNING CAST(token.id AS TEXT) AS id",
			{
				userId=arguments.userId,
				workspaceId=arguments.workspaceId,
				tokenId=arguments.tokenId
			},
			{ returntype="array" }
		);
		return rows.len() ? success( rows[ 1 ].id ) : failure( "not_found" );
	}

	struct function authenticateApiToken(
		required string rawToken,
		string requiredScope = ""
	){
		var candidate = trim( arguments.rawToken );
		if ( !reFind( "^tlk_[0-9a-f]{16}_[A-Za-z0-9_-]{43}$", candidate ) ) {
			return authenticationFailure( "invalid_token", false );
		}
		var publicId = mid( candidate, 5, 16 );
		var rows = queryExecute(
			"SELECT CAST(token.id AS TEXT) AS token_id,
			        CAST(token.workspace_id AS TEXT) AS workspace_id,
			        CAST(token.subject_user_id AS TEXT) AS user_id,
			        CAST(token.scopes AS TEXT) AS scopes,membership.role,workspace.plan
			 FROM api_token token
			 JOIN workspace_member membership
			   ON membership.workspace_id=token.workspace_id
			  AND membership.user_id=token.subject_user_id
			 JOIN app_user subject
			   ON subject.id=token.subject_user_id
			  AND subject.email_verified_at IS NOT NULL
			 JOIN workspace ON workspace.id=token.workspace_id
			 WHERE token.public_id=:publicId
			   AND token.token_hash=:tokenHash
			   AND token.revoked_at IS NULL
			   AND token.expires_at>now()",
			{ publicId=publicId, tokenHash=hashToken( candidate ) },
			{ returntype="array" }
		);
		if ( !rows.len() ) return authenticationFailure( "invalid_token", false );

		var tokenScopes = jsonArray( rows[ 1 ].scopes );
		var requiredScope = lCase( trim( arguments.requiredScope ) );
		if (
			requiredScope.len()
			&& (
				!arrayFindNoCase( variables.scopes, requiredScope )
				|| !arrayFindNoCase( tokenScopes, requiredScope )
				|| (
					rows[ 1 ].role == "viewer"
					&& arrayFindNoCase( variables.writeScopes, requiredScope )
				)
			)
		) return authenticationFailure( "insufficient_scope", true );

		queryExecute(
			"UPDATE api_token
			 SET last_used_at=now()
			 WHERE id=CAST(:tokenId AS UUID)
			   AND (last_used_at IS NULL OR last_used_at<now()-INTERVAL '5 minutes')",
			{ tokenId=rows[ 1 ].token_id }
		);
		return {
			success=true,
			found=true,
			code="ok",
			tokenId=rows[ 1 ].token_id,
			workspaceId=rows[ 1 ].workspace_id,
			userId=rows[ 1 ].user_id,
			role=rows[ 1 ].role,
			plan=rows[ 1 ].plan,
			scopes=tokenScopes
		};
	}

	struct function createEndpoint(
		required string userId,
		required string workspaceId,
		required string name,
		required string url,
		required any eventTypes
	){
		var cleanName = trim( arguments.name );
		var preliminaryAccess = workspaceAccess( arguments.userId, arguments.workspaceId );
		if ( !canManage( preliminaryAccess ) ) return failure( "forbidden" );
		var normalizedEvents = normalizeAllowedValues(
			arguments.eventTypes,
			variables.eventTypes
		);
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !cleanName.len() || cleanName.len() > 120
			|| !normalizedEvents.valid
		) return failure( "invalid" );
		var urlPolicy = webhookUrlPolicyService.validate( trim( arguments.url ) );
		if ( !urlPolicy.allowed ) return failure( "invalid_url" );

		var endpointId = canonicalUuid( createUUID() );
		var secret = webhookCryptoService.generateSecret();
		var protectedSecret = webhookCryptoService.encryptSecret(
			secret=secret,
			workspaceId=arguments.workspaceId,
			endpointId=endpointId
		);
		var outcome = failure( "forbidden" );
		transaction {
			var access = lockedWorkspaceAccess( arguments.userId, arguments.workspaceId );
			if ( !canManage( access ) ) {
				outcome = failure( "forbidden" );
			} else {
				var limits = planLimits( access.plan );
				var activeCount = queryExecute(
					"SELECT COUNT(*) AS total
					 FROM webhook_endpoint
					 WHERE workspace_id=CAST(:workspaceId AS UUID)
					   AND deleted_at IS NULL",
					{ workspaceId=arguments.workspaceId },
					{ returntype="array" }
				)[ 1 ].total;
				if ( val( activeCount ) >= limits.endpointLimit ) {
					outcome = failure( "limit_reached" );
				} else {
					queryExecute(
						"INSERT INTO webhook_endpoint(
						     id,workspace_id,name,url,event_types,secret_ciphertext,
						     secret_nonce,secret_key_version,secret_hint,created_by
						 )
						 VALUES(
						     CAST(:endpointId AS UUID),CAST(:workspaceId AS UUID),:name,:url,
						     CAST(:eventTypes AS JSONB),:ciphertext,:nonce,
						     CAST(:keyVersion AS SMALLINT),:hint,CAST(:userId AS UUID)
						 )",
						{
							endpointId=endpointId,
							workspaceId=arguments.workspaceId,
							name=cleanName,
							url=urlPolicy.url,
							eventTypes=serializeJSON( normalizedEvents.values ),
							ciphertext=protectedSecret.ciphertext,
							nonce=protectedSecret.nonce,
							keyVersion=protectedSecret.keyVersion,
							hint=protectedSecret.hint,
							userId=arguments.userId
						}
					);
					outcome = {
						success=true,
						code="ok",
						id=endpointId,
						endpointId=endpointId,
						name=cleanName,
						secret=secret,
						secretHint=protectedSecret.hint
					};
				}
			}
		}
		return outcome;
	}

	struct function toggleEndpoint(
		required string userId,
		required string workspaceId,
		required string endpointId,
		required boolean enabled
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.endpointId )
		) return failure( "not_found" );
		var rows = queryExecute(
			"UPDATE webhook_endpoint endpoint
			 SET is_enabled=CAST(:enabled AS BOOLEAN),updated_at=now()
			 FROM workspace_member actor
			 WHERE endpoint.id=CAST(:endpointId AS UUID)
			   AND endpoint.workspace_id=CAST(:workspaceId AS UUID)
			   AND endpoint.deleted_at IS NULL
			   AND actor.workspace_id=endpoint.workspace_id
			   AND actor.user_id=CAST(:userId AS UUID)
			   AND actor.role IN ('owner','admin')
			 RETURNING CAST(endpoint.id AS TEXT) AS id",
			{
				userId=arguments.userId,
				workspaceId=arguments.workspaceId,
				endpointId=arguments.endpointId,
				enabled=arguments.enabled
			},
			{ returntype="array" }
		);
		return rows.len() ? success( rows[ 1 ].id ) : failure( "not_found" );
	}

	struct function deleteEndpoint(
		required string userId,
		required string workspaceId,
		required string endpointId
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.endpointId )
		) return failure( "not_found" );
		var rows = queryExecute(
			"UPDATE webhook_endpoint endpoint
			 SET is_enabled=false,deleted_at=now(),updated_at=now()
			 FROM workspace_member actor
			 WHERE endpoint.id=CAST(:endpointId AS UUID)
			   AND endpoint.workspace_id=CAST(:workspaceId AS UUID)
			   AND endpoint.deleted_at IS NULL
			   AND actor.workspace_id=endpoint.workspace_id
			   AND actor.user_id=CAST(:userId AS UUID)
			   AND actor.role IN ('owner','admin')
			 RETURNING CAST(endpoint.id AS TEXT) AS id",
			{
				userId=arguments.userId,
				workspaceId=arguments.workspaceId,
				endpointId=arguments.endpointId
			},
			{ returntype="array" }
		);
		return rows.len() ? success( rows[ 1 ].id ) : failure( "not_found" );
	}

	struct function queueTestEndpoint(
		required string userId,
		required string workspaceId,
		required string endpointId
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.endpointId )
		) return failure( "not_found" );
		var endpointRows = queryExecute(
			"SELECT endpoint.url
			 FROM webhook_endpoint endpoint
			 JOIN workspace_member actor
			   ON actor.workspace_id=endpoint.workspace_id
			  AND actor.user_id=CAST(:userId AS UUID)
			  AND actor.role IN ('owner','admin')
			 WHERE endpoint.id=CAST(:endpointId AS UUID)
			   AND endpoint.workspace_id=CAST(:workspaceId AS UUID)
			   AND endpoint.is_enabled=true
			   AND endpoint.deleted_at IS NULL",
			{
				userId=arguments.userId,
				workspaceId=arguments.workspaceId,
				endpointId=arguments.endpointId
			},
			{ returntype="array" }
		);
		if ( !endpointRows.len() ) return failure( "not_found" );
		var urlPolicy = webhookUrlPolicyService.validate(
			url=endpointRows[ 1 ].url,
			forDelivery=true
		);
		if ( !urlPolicy.allowed ) return failure( "invalid_url" );

		var eventId = canonicalUuid( createUUID() );
		var envelope = {};
		envelope[ "id" ] = eventId;
		envelope[ "type" ] = "integration.test";
		envelope[ "version" ] = 1;
		envelope[ "createdAt" ] = createObject( "java", "java.time.Instant" )
			.now()
			.toString();
		envelope[ "workspaceId" ] = lCase( arguments.workspaceId );
		envelope[ "data" ] = {
			"endpointId"=lCase( arguments.endpointId ),
			"message"="TaborLane webhook test"
		};
		var requestBody = serializeJSON( envelope );
		var inserted = queryExecute(
			"INSERT INTO webhook_delivery(
			     workspace_id,endpoint_id,event_id,event_type,event_version,
			     envelope,request_body
			 )
			 SELECT endpoint.workspace_id,endpoint.id,CAST(:eventId AS UUID),
			        'integration.test',1,CAST(:envelope AS JSONB),:requestBody
			 FROM webhook_endpoint endpoint
			 JOIN workspace_member actor
			   ON actor.workspace_id=endpoint.workspace_id
			  AND actor.user_id=CAST(:userId AS UUID)
			  AND actor.role IN ('owner','admin')
			 WHERE endpoint.id=CAST(:endpointId AS UUID)
			   AND endpoint.workspace_id=CAST(:workspaceId AS UUID)
			   AND endpoint.is_enabled=true AND endpoint.deleted_at IS NULL
			 RETURNING CAST(id AS TEXT) AS id",
			{
				eventId=eventId,
				envelope=serializeJSON( envelope ),
				requestBody=requestBody,
				userId=arguments.userId,
				endpointId=arguments.endpointId,
				workspaceId=arguments.workspaceId
			},
			{ returntype="array" }
		);
		return inserted.len()
			? { success=true,code="ok",id=inserted[ 1 ].id,eventId=eventId }
			: failure( "not_found" );
	}

	private struct function workspaceAccess(
		required string userId,
		required string workspaceId
	){
		if ( !isCanonicalUuid( arguments.userId ) || !isCanonicalUuid( arguments.workspaceId ) ) {
			return { found=false };
		}
		var rows = queryExecute(
			"SELECT membership.role,workspace.plan
			 FROM workspace_member membership
			 JOIN workspace ON workspace.id=membership.workspace_id
			 WHERE membership.workspace_id=CAST(:workspaceId AS UUID)
			   AND membership.user_id=CAST(:userId AS UUID)",
			{ userId=arguments.userId,workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		return rows.len()
			? { found=true,role=rows[ 1 ].role,plan=rows[ 1 ].plan }
			: { found=false };
	}

	private struct function lockedWorkspaceAccess(
		required string userId,
		required string workspaceId
	){
		var rows = queryExecute(
			"SELECT membership.role,workspace.plan
			 FROM workspace
			 JOIN workspace_member membership
			   ON membership.workspace_id=workspace.id
			  AND membership.user_id=CAST(:userId AS UUID)
			 WHERE workspace.id=CAST(:workspaceId AS UUID)
			 FOR UPDATE OF workspace,membership",
			{ userId=arguments.userId,workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		return rows.len()
			? { found=true,role=rows[ 1 ].role,plan=rows[ 1 ].plan }
			: { found=false };
	}

	private struct function planLimits( required string plan ){
		var premium = compareNoCase( arguments.plan, "premium" ) == 0;
		return {
			tokenLimit=premium ? 10 : 1,
			endpointLimit=premium ? 10 : 1
		};
	}

	private boolean function canManage( required struct access ){
		return ( arguments.access.found ?: false )
			&& listFindNoCase( "owner,admin", arguments.access.role ) > 0;
	}

	private struct function normalizeAllowedValues(
		required any input,
		required array allowed
	){
		var incoming = collectionArray( arguments.input );
		if ( !incoming.len() ) return { valid=false,values=[] };
		var known = {};
		for ( var allowedValue in arguments.allowed ) known[ allowedValue ] = true;
		var seen = {};
		var values = [];
		for ( var rawValue in incoming ) {
			var value = lCase( trim( toString( rawValue ) ) );
			if ( !structKeyExists( known, value ) ) return { valid=false,values=[] };
			if ( !structKeyExists( seen, value ) ) {
				seen[ value ] = true;
				values.append( value );
			}
		}
		return { valid=values.len() > 0,values=values };
	}

	private array function collectionArray( required any value ){
		if ( isArray( arguments.value ) ) return duplicate( arguments.value );
		if ( isSimpleValue( arguments.value ) ) {
			var text = trim( toString( arguments.value ) );
			if ( isJSON( text ) ) {
				var decoded = deserializeJSON( text );
				if ( isArray( decoded ) ) return decoded;
			}
			return text.len() ? listToArray( text ) : [];
		}
		return [];
	}

	private array function jsonArray( required any value ){
		if ( isArray( arguments.value ) ) return duplicate( arguments.value );
		if ( isSimpleValue( arguments.value ) && isJSON( toString( arguments.value ) ) ) {
			var decoded = deserializeJSON( toString( arguments.value ) );
			return isArray( decoded ) ? decoded : [];
		}
		return [];
	}

	private any function randomBytes( required numeric length ){
		var bytes = createObject( "java", "java.nio.ByteBuffer" )
			.allocate( javacast( "int", arguments.length ) )
			.array();
		createObject( "java", "java.security.SecureRandom" ).init().nextBytes( bytes );
		return bytes;
	}

	private string function base64UrlEncode( required any value ){
		return createObject( "java", "java.util.Base64" )
			.getUrlEncoder()
			.withoutPadding()
			.encodeToString( arguments.value );
	}

	private string function hashToken( required string token ){
		return lCase( hash( arguments.token, "SHA-256" ) );
	}

	private struct function success( required string id ){
		return { success=true,code="ok",id=arguments.id };
	}

	private struct function failure( required string code ){
		return { success=false,code=arguments.code };
	}

	private struct function authenticationFailure(
		required string code,
		required boolean found
	){
		return { success=false,found=arguments.found,code=arguments.code };
	}

	private boolean function isCanonicalUuid( required string value ){
		return reFindNoCase(
			"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
			trim( arguments.value )
		) > 0;
	}

	private string function canonicalUuid( required string value ){
		var compact = lCase( replace( arguments.value, "-", "", "all" ) );
		if ( !reFind( "^[0-9a-f]{32}$", compact ) ) {
			throw( type="Integration.InvalidUuid",message="Could not generate a UUID." );
		}
		return left( compact, 8 )
			& "-" & mid( compact, 9, 4 )
			& "-" & mid( compact, 13, 4 )
			& "-" & mid( compact, 17, 4 )
			& "-" & right( compact, 12 );
	}

}
