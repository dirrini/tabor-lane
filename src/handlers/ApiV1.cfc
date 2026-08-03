component {

	property name="integrationService" inject="IntegrationService";
	property name="integrationApiService" inject="IntegrationApiService";
	property name="boardService" inject="BoardService";
	property name="rateLimitService" inject="RateLimitService";

	this.allowedMethods = {
		boards="GET",
		board="GET",
		boardCards="GET",
		card="GET",
		createCard="POST",
		patchCard="PATCH",
		moveCard="POST"
	};

	function aroundHandler( event, rc, prc, targetAction, eventArguments ){
		prc.apiRequestId = createUUID();
		event.setHTTPHeader( name="Cache-Control", value="no-store" );
		event.setHTTPHeader( name="Pragma", value="no-cache" );
		event.setHTTPHeader( name="Vary", value="Authorization" );
		event.setHTTPHeader( name="X-Content-Type-Options", value="nosniff" );
		event.setHTTPHeader( name="X-Request-ID", value=prc.apiRequestId );

		var scopeByAction = {
			boards="boards:read",
			board="boards:read",
			boardCards="cards:read",
			card="cards:read",
			createCard="cards:create",
			patchCard="cards:update",
			moveCard="cards:move"
		};
		var rawToken = bearerToken();
		if ( !rawToken.len() ) {
			unauthorized( event, "invalid_token", "A valid Bearer token is required." );
			return;
		}

		var principal = {};
		try {
			principal = integrationService.authenticateApiToken(
				rawToken=rawToken,
				requiredScope=scopeByAction[
					listLast( event.getCurrentEvent(), "." )
				]
			);
		} catch ( any exception ) {
			internalError( event, prc, exception );
			return;
		}
		if ( !( principal.success ?: false ) ) {
			if ( ( principal.code ?: "" ) == "insufficient_scope" ) {
				renderError(
					event,
					403,
					"insufficient_scope",
					"The token does not grant the required scope."
				);
			} else {
				unauthorized( event, "invalid_token", "A valid Bearer token is required." );
			}
			return;
		}

		var requestsPerMinute = ( principal.plan ?: "free" ) == "premium" ? 600 : 120;
		if (
			!rateLimitService.allow(
				"api-token:#principal.tokenId#",
				requestsPerMinute,
				60
			)
		) {
			event.setHTTPHeader( name="Retry-After", value="60" );
			renderError(
				event,
				429,
				"rate_limit_exceeded",
				"Too many requests. Try again later."
			);
			return;
		}
		prc.apiPrincipal = principal;
		return arguments.targetAction(
			event=arguments.event,
			rc=arguments.rc,
			prc=arguments.prc
		);
	}

	function boards( event, rc, prc ){
		try {
			renderDataResponse(
				event,
				integrationApiService.listBoards( prc.apiPrincipal )
			);
		} catch ( any exception ) {
			internalError( event, prc, exception );
		}
	}

	function board( event, rc, prc ){
		if ( !isCanonicalUuid( rc.boardId ?: "" ) ) {
			return renderError( event, 400, "invalid_id", "The board ID is invalid." );
		}
		try {
			var result = integrationApiService.getBoard(
				prc.apiPrincipal,
				lCase( rc.boardId )
			);
			if ( !result.found ) return notFound( event );
			renderDataResponse( event, result.board );
		} catch ( any exception ) {
			internalError( event, prc, exception );
		}
	}

	function boardCards( event, rc, prc ){
		if ( !isCanonicalUuid( rc.boardId ?: "" ) ) {
			return renderError( event, 400, "invalid_id", "The board ID is invalid." );
		}
		try {
			var result = integrationApiService.listBoardCards(
				prc.apiPrincipal,
				lCase( rc.boardId )
			);
			if ( !result.found ) return notFound( event );
			renderDataResponse( event, result.cards );
		} catch ( any exception ) {
			internalError( event, prc, exception );
		}
	}

	function card( event, rc, prc ){
		if ( !isCanonicalUuid( rc.cardId ?: "" ) ) {
			return renderError( event, 400, "invalid_id", "The card ID is invalid." );
		}
		try {
			var result = integrationApiService.getCard(
				prc.apiPrincipal,
				lCase( rc.cardId )
			);
			if ( !result.found ) return notFound( event );
			renderDataResponse( event, result.card );
		} catch ( any exception ) {
			internalError( event, prc, exception );
		}
	}

	function createCard( event, rc, prc ){
		var parsed = jsonBody();
		if ( !parsed.success ) {
			return renderError( event, 400, parsed.code, parsed.message );
		}
		var validation = validateCreate( parsed.body );
		if ( !validation.success ) {
			return renderError( event, 422, validation.code, validation.message );
		}

		try {
			var result = boardService.createCard(
				userId=prc.apiPrincipal.userId,
				workspaceId=prc.apiPrincipal.workspaceId,
				columnId=validation.data.laneId,
				title=validation.data.title,
				description=validation.data.description
			);
			if ( !result.success ) return domainFailure( event, result );

			var data = structNew( "ordered" );
			data[ "id" ] = result.cardId;
			data[ "boardId" ] = result.boardId;
			data[ "laneId" ] = validation.data.laneId;
			event.setHTTPHeader(
				name="Location",
				value="/api/v1/cards/#result.cardId#"
			);
			renderDataResponse( event, data, 201 );
		} catch ( any exception ) {
			internalError( event, prc, exception );
		}
	}

	function patchCard( event, rc, prc ){
		if ( !isCanonicalUuid( rc.cardId ?: "" ) ) {
			return renderError( event, 400, "invalid_id", "The card ID is invalid." );
		}
		var parsed = jsonBody();
		if ( !parsed.success ) {
			return renderError( event, 400, parsed.code, parsed.message );
		}
		var validation = validatePatch( parsed.body );
		if ( !validation.success ) {
			return renderError( event, 422, validation.code, validation.message );
		}

		try {
			var result = boardService.patchCard(
				userId=prc.apiPrincipal.userId,
				workspaceId=prc.apiPrincipal.workspaceId,
				cardId=lCase( rc.cardId ),
				data=validation.data
			);
			if ( !result.success ) return domainFailure( event, result );

			var data = structNew( "ordered" );
			data[ "id" ] = lCase( rc.cardId );
			data[ "boardId" ] = result.boardId;
			data[ "version" ] = val( result.version );
			renderDataResponse( event, data );
		} catch ( any exception ) {
			internalError( event, prc, exception );
		}
	}

	function moveCard( event, rc, prc ){
		if ( !isCanonicalUuid( rc.cardId ?: "" ) ) {
			return renderError( event, 400, "invalid_id", "The card ID is invalid." );
		}
		var parsed = jsonBody();
		if ( !parsed.success ) {
			return renderError( event, 400, parsed.code, parsed.message );
		}
		var validation = validateMove( parsed.body );
		if ( !validation.success ) {
			return renderError( event, 422, validation.code, validation.message );
		}

		try {
			var result = boardService.moveCard(
				userId=prc.apiPrincipal.userId,
				workspaceId=prc.apiPrincipal.workspaceId,
				cardId=lCase( rc.cardId ),
				columnId=validation.data.laneId,
				beforeCardId=validation.data.beforeCardId
			);
			if ( !result.success ) return domainFailure( event, result );

			var data = structNew( "ordered" );
			data[ "id" ] = lCase( rc.cardId );
			data[ "revision" ] = result.revision ?: "";
			renderDataResponse( event, data );
		} catch ( any exception ) {
			internalError( event, prc, exception );
		}
	}

	private struct function jsonBody(){
		var requestData = getHttpRequestData();
		var contentType = requestHeader( requestData.headers ?: {}, "Content-Type" );
		if ( compareNoCase( trim( listFirst( contentType, ";" ) ), "application/json" ) ) {
			return {
				success=false,
				code="invalid_content_type",
				message="Content-Type must be application/json."
			};
		}

		var rawBody = toString( requestData.content ?: "" );
		if ( !trim( rawBody ).len() || len( rawBody ) > 262144 ) {
			return {
				success=false,
				code="invalid_json",
				message="The JSON request body is empty or too large."
			};
		}
		try {
			var body = deserializeJSON( rawBody );
			if ( !isStruct( body ) ) {
				return {
					success=false,
					code="invalid_json",
					message="The JSON request body must be an object."
				};
			}
			return { success=true,body=body };
		} catch ( any exception ) {
			return {
				success=false,
				code="invalid_json",
				message="The JSON request body is malformed."
			};
		}
	}

	private struct function validateCreate( required struct body ){
		if ( !hasOnlyKeys( arguments.body, "laneId,title,description" ) ) {
			return invalidValidation( "unknown_field", "The request contains an unknown field." );
		}
		if (
			!structKeyExists( arguments.body, "laneId" )
			|| !isCanonicalUuid( arguments.body.laneId )
			|| !structKeyExists( arguments.body, "title" )
			|| !isSimpleValue( arguments.body.title )
		) {
			return invalidValidation( "invalid_card", "laneId and title are required." );
		}
		var title = trim( toString( arguments.body.title ) );
		if ( !title.len() || title.len() > 255 ) {
			return invalidValidation( "invalid_title", "title must contain 1 to 255 characters." );
		}
		var description = "";
		if ( structKeyExists( arguments.body, "description" ) ) {
			if ( !isSimpleValue( arguments.body.description ) ) {
				return invalidValidation( "invalid_description", "description must be a string." );
			}
			description = trim( toString( arguments.body.description ) );
			if ( description.len() > 20000 ) {
				return invalidValidation( "invalid_description", "description is too long." );
			}
		}
		return {
			success=true,
			data={
				laneId=lCase( arguments.body.laneId ),
				title=title,
				description=description
			}
		};
	}

	private struct function validatePatch( required struct body ){
		var allowed = "title,description,priority,dueDate,labels,assigneeIds,isBlocked,expectedVersion";
		if ( !hasOnlyKeys( arguments.body, allowed ) ) {
			return invalidValidation( "unknown_field", "The request contains an unknown field." );
		}
		var patch = {};
		var editableCount = 0;

		if ( structKeyExists( arguments.body, "title" ) ) {
			if ( !isSimpleValue( arguments.body.title ) ) {
				return invalidValidation( "invalid_title", "title must be a string." );
			}
			var title = trim( toString( arguments.body.title ) );
			if ( !title.len() || title.len() > 255 ) {
				return invalidValidation( "invalid_title", "title must contain 1 to 255 characters." );
			}
			patch[ "title" ] = title;
			editableCount++;
		}
		if ( structKeyExists( arguments.body, "description" ) ) {
			if ( !isSimpleValue( arguments.body.description ) ) {
				return invalidValidation( "invalid_description", "description must be a string." );
			}
			var description = trim( toString( arguments.body.description ) );
			if ( description.len() > 20000 ) {
				return invalidValidation( "invalid_description", "description is too long." );
			}
			patch[ "description" ] = description;
			editableCount++;
		}
		if ( structKeyExists( arguments.body, "priority" ) ) {
			if (
				!isSimpleValue( arguments.body.priority )
				|| !listFindNoCase(
					"none,low,medium,high,urgent",
					toString( arguments.body.priority )
				)
			) {
				return invalidValidation( "invalid_priority", "priority is invalid." );
			}
			patch[ "priority" ] = lCase( arguments.body.priority );
			editableCount++;
		}
		if ( structKeyExists( arguments.body, "dueDate" ) ) {
			if ( !isSimpleValue( arguments.body.dueDate ) ) {
				return invalidValidation( "invalid_due_date", "dueDate must be a date or an empty string." );
			}
			var dueDate = trim( toString( arguments.body.dueDate ) );
			if (
				dueDate.len()
				&& (
					!reFind( "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", dueDate )
					|| !isValid( "date", dueDate )
				)
			) {
				return invalidValidation( "invalid_due_date", "dueDate must use YYYY-MM-DD." );
			}
			patch[ "dueDate" ] = dueDate;
			editableCount++;
		}
		if ( structKeyExists( arguments.body, "labels" ) ) {
			if ( !isArray( arguments.body.labels ) || arguments.body.labels.len() > 10 ) {
				return invalidValidation( "invalid_labels", "labels must be an array with at most 10 items." );
			}
			var labels = [];
			for ( var labelValue in arguments.body.labels ) {
				if ( !isSimpleValue( labelValue ) ) {
					return invalidValidation( "invalid_labels", "Every label must be a string." );
				}
				var label = trim( toString( labelValue ) );
				if (
					!label.len()
					|| label.len() > 40
					|| find( ",", label )
					|| arrayFindNoCase( labels, label )
				) {
					return invalidValidation( "invalid_labels", "Labels must be unique and contain 1 to 40 characters without commas." );
				}
				labels.append( label );
			}
			patch[ "labels" ] = labels;
			editableCount++;
		}
		if ( structKeyExists( arguments.body, "assigneeIds" ) ) {
			if ( !isArray( arguments.body.assigneeIds ) || arguments.body.assigneeIds.len() > 50 ) {
				return invalidValidation( "invalid_assignees", "assigneeIds must be an array with at most 50 items." );
			}
			var assigneeIds = [];
			for ( var assigneeId in arguments.body.assigneeIds ) {
				if (
					!isCanonicalUuid( assigneeId )
					|| arrayFindNoCase( assigneeIds, assigneeId )
				) {
					return invalidValidation( "invalid_assignees", "assigneeIds contains an invalid or duplicate ID." );
				}
				assigneeIds.append( lCase( assigneeId ) );
			}
			patch[ "assigneeIds" ] = assigneeIds;
			editableCount++;
		}
		if ( structKeyExists( arguments.body, "isBlocked" ) ) {
			if ( !isBoolean( arguments.body.isBlocked ) ) {
				return invalidValidation( "invalid_blocked_state", "isBlocked must be a boolean." );
			}
			patch[ "isBlocked" ] = arguments.body.isBlocked;
			editableCount++;
		}
		if ( structKeyExists( arguments.body, "expectedVersion" ) ) {
			if (
				!isNumeric( arguments.body.expectedVersion )
				|| val( arguments.body.expectedVersion ) < 1
				|| floor( val( arguments.body.expectedVersion ) )
					!= val( arguments.body.expectedVersion )
			) {
				return invalidValidation( "invalid_version", "expectedVersion must be a positive integer." );
			}
			patch[ "expectedVersion" ] = val( arguments.body.expectedVersion );
		}
		if ( !editableCount ) {
			return invalidValidation( "empty_patch", "At least one editable field is required." );
		}
		return { success=true,data=patch };
	}

	private struct function validateMove( required struct body ){
		if ( !hasOnlyKeys( arguments.body, "laneId,beforeCardId" ) ) {
			return invalidValidation( "unknown_field", "The request contains an unknown field." );
		}
		if (
			!structKeyExists( arguments.body, "laneId" )
			|| !isCanonicalUuid( arguments.body.laneId )
		) {
			return invalidValidation( "invalid_lane", "laneId is required and must be a UUID." );
		}
		var beforeCardId = "";
		if ( structKeyExists( arguments.body, "beforeCardId" ) ) {
			if (
				!isSimpleValue( arguments.body.beforeCardId )
				|| (
					trim( toString( arguments.body.beforeCardId ) ).len()
					&& !isCanonicalUuid( arguments.body.beforeCardId )
				)
			) {
				return invalidValidation( "invalid_position", "beforeCardId must be a UUID or an empty string." );
			}
			beforeCardId = lCase( trim( toString( arguments.body.beforeCardId ) ) );
		}
		return {
			success=true,
			data={
				laneId=lCase( arguments.body.laneId ),
				beforeCardId=beforeCardId
			}
		};
	}

	private boolean function hasOnlyKeys(
		required struct value,
		required string allowedKeys
	){
		for ( var key in arguments.value ) {
			if ( !listFindNoCase( arguments.allowedKeys, key ) ) return false;
		}
		return true;
	}

	private struct function invalidValidation(
		required string code,
		required string message
	){
		return {
			success=false,
			code=arguments.code,
			message=arguments.message
		};
	}

	private string function bearerToken(){
		var headers = getHttpRequestData().headers ?: {};
		var authorization = trim( requestHeader( headers, "Authorization" ) );
		if (
			authorization.len() > 512
			|| !reFindNoCase(
				"^Bearer[[:space:]]+[A-Za-z0-9._~-]+$",
				authorization
			)
		) return "";
		return reReplaceNoCase(
			authorization,
			"^Bearer[[:space:]]+",
			"",
			"one"
		);
	}

	private string function requestHeader(
		required any headers,
		required string name
	){
		for ( var key in arguments.headers ) {
			if ( !compareNoCase( key, arguments.name ) ) {
				return toString( arguments.headers[ key ] );
			}
		}
		return "";
	}

	private boolean function isCanonicalUuid( required any value ){
		return isSimpleValue( arguments.value )
			&& reFindNoCase(
				"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
				trim( toString( arguments.value ) )
			) > 0;
	}

	private any function domainFailure(
		required any event,
		required struct result
	){
		var code = arguments.result.code ?: "not_found";
		if ( code == "wip_limit" || code == "version_conflict" ) {
			var details = {};
			if ( structKeyExists( arguments.result, "version" ) ) {
				details[ "currentVersion" ] = val( arguments.result.version );
			}
			return renderError(
				arguments.event,
				409,
				code,
				code == "wip_limit"
					? "The lane WIP limit has been reached."
					: "The card has changed since it was read.",
				details
			);
		}
		if ( code == "read_only" ) {
			return renderError(
				arguments.event,
				403,
				"read_only",
				"The current API principal cannot modify this resource."
			);
		}
		if (
			listFindNoCase(
				"invalid,invalid_assignees,invalid_position",
				code
			)
		) {
			return renderError(
				arguments.event,
				422,
				code,
				"The requested operation is not valid."
			);
		}
		return notFound( arguments.event );
	}

	private any function unauthorized(
		required any event,
		required string code,
		required string message
	){
		arguments.event.setHTTPHeader(
			name="WWW-Authenticate",
			value='Bearer realm="TaborLane"'
		);
		return renderError(
			arguments.event,
			401,
			arguments.code,
			arguments.message
		);
	}

	private any function notFound( required any event ){
		return renderError(
			arguments.event,
			404,
			"not_found",
			"The requested resource was not found."
		);
	}

	private any function renderDataResponse(
		required any event,
		required any data,
		numeric statusCode=200
	){
		var payload = structNew( "ordered" );
		payload[ "data" ] = arguments.data;
		return arguments.event.renderData(
			type="json",
			data=payload,
			statusCode=arguments.statusCode
		);
	}

	private any function renderError(
		required any event,
		required numeric statusCode,
		required string code,
		required string message,
		struct details={}
	){
		var error = structNew( "ordered" );
		error[ "code" ] = arguments.code;
		error[ "message" ] = arguments.message;
		if ( structCount( arguments.details ) ) error[ "details" ] = arguments.details;
		var payload = structNew( "ordered" );
		payload[ "error" ] = error;
		return arguments.event.renderData(
			type="json",
			data=payload,
			statusCode=arguments.statusCode
		);
	}

	private any function internalError(
		required any event,
		required struct prc,
		required any exception
	){
		writeLog(
			file="application",
			type="error",
			text="API request #arguments.prc.apiRequestId# failed: #arguments.exception.message#"
		);
		return renderError(
			arguments.event,
			500,
			"internal_error",
			"The request could not be completed."
		);
	}

}
