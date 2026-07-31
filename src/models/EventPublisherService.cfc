component singleton {

	struct function publish(
		required string workspaceId,
		required string eventType,
		required string aggregateType,
		required string aggregateId,
		string actorId = "",
		array recipientUserIds = [],
		struct payload = {},
		string deduplicationKey = ""
	){
		var workspaceId = trim( arguments.workspaceId );
		var aggregateId = trim( arguments.aggregateId );
		var actorId = trim( arguments.actorId );
		var eventType = lCase( trim( arguments.eventType ) );
		var aggregateType = lCase( trim( arguments.aggregateType ) );
		var deduplicationKey = trim( arguments.deduplicationKey );

		if ( !isCanonicalUuid( workspaceId ) || !isCanonicalUuid( aggregateId ) ) {
			invalid( "invalid_id" );
		}
		if ( actorId.len() && !isCanonicalUuid( actorId ) ) {
			invalid( "invalid_actor" );
		}
		if ( !reFind( "^[a-z0-9][a-z0-9._-]{0,159}$", eventType ) ) {
			invalid( "invalid_event_type" );
		}
		if ( !reFind( "^[a-z0-9][a-z0-9._-]{0,79}$", aggregateType ) ) {
			invalid( "invalid_aggregate_type" );
		}
		if ( deduplicationKey.len() > 255 ) {
			invalid( "invalid_deduplication_key" );
		}

		var uniqueRecipients = {};
		var recipients = [];
		for ( var recipientId in arguments.recipientUserIds ) {
			var normalizedRecipientId = lCase( trim( toString( recipientId ) ) );
			if ( !isCanonicalUuid( normalizedRecipientId ) ) {
				invalid( "invalid_recipient" );
			}
			if ( !structKeyExists( uniqueRecipients, normalizedRecipientId ) ) {
				uniqueRecipients[ normalizedRecipientId ] = true;
				recipients.append( normalizedRecipientId );
			}
		}

		var eventId = canonicalUuid( createUUID() );
		var insertedRows = queryExecute(
			"INSERT INTO outbox_event(
			     id,workspace_id,event_type,aggregate_type,aggregate_id,actor_id,
			     recipient_user_ids,payload,deduplication_key,available_at
			 )
			 SELECT CAST(:eventId AS UUID),workspace.id,:eventType,:aggregateType,
			        CAST(:aggregateId AS UUID),CAST(NULLIF(:actorId,'') AS UUID),
			        CAST(:recipientUserIds AS JSONB),CAST(:payload AS JSONB),
			        NULLIF(:deduplicationKey,''),now()
			 FROM workspace
			 WHERE workspace.id=CAST(:workspaceId AS UUID)
			 ON CONFLICT (workspace_id,deduplication_key)
			     WHERE deduplication_key IS NOT NULL
			 DO NOTHING
			 RETURNING CAST(id AS TEXT) AS id",
			{
				eventId=eventId,
				workspaceId=workspaceId,
				eventType=eventType,
				aggregateType=aggregateType,
				aggregateId=aggregateId,
				actorId=actorId,
				recipientUserIds=serializeJSON( recipients ),
				payload=serializeJSON( arguments.payload ),
				deduplicationKey=deduplicationKey
			},
			{ returntype="array" }
		);
		if ( insertedRows.len() ) return success( insertedRows[ 1 ].id, false );

		if ( deduplicationKey.len() ) {
			var duplicateRows = queryExecute(
				"SELECT CAST(id AS TEXT) AS id
				 FROM outbox_event
				 WHERE workspace_id=CAST(:workspaceId AS UUID)
				   AND deduplication_key=:deduplicationKey",
				{
					workspaceId=workspaceId,
					deduplicationKey=deduplicationKey
				},
				{ returntype="array" }
			);
			if ( duplicateRows.len() ) return success( duplicateRows[ 1 ].id, true );
		}
		invalid( "not_found" );
	}

	private struct function success( required string id, required boolean duplicate ){
		var result = {};
		result[ "success" ] = true;
		result[ "code" ] = "ok";
		result[ "id" ] = arguments.id;
		result[ "duplicate" ] = arguments.duplicate;
		return result;
	}

	private void function invalid( required string code ){
		throw(
			type="EventPublisher.#arguments.code#",
			message="The outbox event could not be published.",
			detail=arguments.code
		);
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
			throw(
				type="EventPublisher.InvalidUuid",
				message="Could not generate a valid event UUID."
			);
		}
		return left( compact, 8 )
			& "-" & mid( compact, 9, 4 )
			& "-" & mid( compact, 13, 4 )
			& "-" & mid( compact, 17, 4 )
			& "-" & right( compact, 12 );
	}

}
