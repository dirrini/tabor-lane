component singleton {

	variables.environment = server.system.environment;

	struct function processBatch( numeric batchSize = 0 ){
		var effectiveBatchSize = arguments.batchSize > 0
			? boundedInteger( arguments.batchSize, 50, 1, 500 )
			: environmentInteger( "OUTBOX_BATCH_SIZE", 50, 1, 500 );
		var maxAttempts = environmentInteger( "OUTBOX_MAX_ATTEMPTS", 8, 1, 25 );
		var claimTimeoutSeconds = environmentInteger(
			"OUTBOX_CLAIM_TIMEOUT_SECONDS",
			300,
			30,
			3600
		);
		var workerId = canonicalUuid( createUUID() );
		var claimedRows = [];

		transaction {
			queryExecute(
				"UPDATE outbox_event
				 SET failed_at=now(),
				     claimed_at=NULL,
				     claimed_by=NULL,
				     last_error=COALESCE(
				         NULLIF(last_error,''),
				         'Maximum processing attempts reached after a stale claim'
				     )
				 WHERE processed_at IS NULL
				   AND failed_at IS NULL
				   AND attempts>=CAST(:maxAttempts AS INTEGER)
				   AND (
				       claimed_at IS NULL
				       OR claimed_at<now()-make_interval(
				           secs => CAST(:claimTimeoutSeconds AS INTEGER)
				       )
				   )",
				{
					maxAttempts=maxAttempts,
					claimTimeoutSeconds=claimTimeoutSeconds
				}
			);

			claimedRows = queryExecute(
				"WITH candidates AS MATERIALIZED (
				     SELECT id
				     FROM outbox_event
				     WHERE processed_at IS NULL
				       AND failed_at IS NULL
				       AND attempts<CAST(:maxAttempts AS INTEGER)
				       AND available_at<=now()
				       AND (
				           claimed_at IS NULL
				           OR claimed_at<now()-make_interval(
				               secs => CAST(:claimTimeoutSeconds AS INTEGER)
				           )
				       )
				     ORDER BY available_at,created_at,id
				     FOR UPDATE SKIP LOCKED
				     LIMIT CAST(:batchSize AS INTEGER)
				 )
				 UPDATE outbox_event event_record
				 SET claimed_at=now(),
				     claimed_by=:workerId,
				     attempts=event_record.attempts+1
				 FROM candidates
				 WHERE event_record.id=candidates.id
				 RETURNING CAST(event_record.id AS TEXT) AS id,event_record.attempts",
				{
					maxAttempts=maxAttempts,
					claimTimeoutSeconds=claimTimeoutSeconds,
					batchSize=effectiveBatchSize,
					workerId=workerId
				},
				{ returntype="array" }
			);
		}

		var result = {};
		result[ "success" ] = true;
		result[ "workerId" ] = workerId;
		result[ "claimed" ] = claimedRows.len();
		result[ "processed" ] = 0;
		result[ "retried" ] = 0;
		result[ "failed" ] = 0;
		result[ "notificationsCreated" ] = 0;

		for ( var claimedEvent in claimedRows ) {
			try {
				var notificationRows = [];
				var processedRows = [];
				transaction {
					notificationRows = queryExecute(
						"INSERT INTO app_notification(
						     event_id,workspace_id,user_id,notification_type,actor_id,
						     aggregate_type,aggregate_id,payload,created_at
						 )
						 SELECT event_record.id,event_record.workspace_id,membership.user_id,
						        event_record.event_type,event_record.actor_id,
						        event_record.aggregate_type,event_record.aggregate_id,
						        event_record.payload,event_record.created_at
						 FROM outbox_event event_record
						 CROSS JOIN LATERAL jsonb_array_elements_text(
						     event_record.recipient_user_ids
						 ) recipient(user_id)
						 JOIN workspace_member membership
						   ON membership.workspace_id=event_record.workspace_id
						  AND CAST(membership.user_id AS TEXT)=lower(recipient.user_id)
						 LEFT JOIN card card_record
						   ON lower(event_record.aggregate_type)='card'
						  AND card_record.id=event_record.aggregate_id
						  AND card_record.workspace_id=event_record.workspace_id
						 LEFT JOIN board board_record
						   ON board_record.id=card_record.board_id
						  AND board_record.workspace_id=card_record.workspace_id
						 LEFT JOIN board_column lane_record
						   ON lane_record.id=card_record.column_id
						  AND lane_record.board_id=card_record.board_id
						 WHERE event_record.id=CAST(:eventId AS UUID)
						   AND event_record.claimed_by=:workerId
						   AND event_record.processed_at IS NULL
						   AND event_record.failed_at IS NULL
						   AND membership.user_id IS DISTINCT FROM event_record.actor_id
						   AND (
						       lower(event_record.aggregate_type)<>'card'
						       OR (
						           card_record.id IS NOT NULL
						           AND card_record.archived_at IS NULL
						           AND board_record.is_archived=false
						           AND lane_record.is_archived=false
						           AND (
						               lane_record.is_hidden_from_members=false
						               OR membership.role IN ('owner','admin')
						           )
						       )
						   )
						 ON CONFLICT (event_id,user_id) DO NOTHING
						 RETURNING CAST(id AS TEXT) AS id",
						{
							eventId=claimedEvent.id,
							workerId=workerId
						},
						{ returntype="array" }
					);

					processedRows = queryExecute(
						"UPDATE outbox_event
						 SET processed_at=now(),
						     claimed_at=NULL,
						     claimed_by=NULL,
						     last_error=NULL
						 WHERE id=CAST(:eventId AS UUID)
						   AND claimed_by=:workerId
						   AND processed_at IS NULL
						   AND failed_at IS NULL
						 RETURNING CAST(id AS TEXT) AS id",
						{
							eventId=claimedEvent.id,
							workerId=workerId
						},
						{ returntype="array" }
					);
					if ( !processedRows.len() ) {
						throw(
							type="OutboxProcessor.LostClaim",
							message="The outbox claim was no longer owned by this worker."
						);
					}
				}
				result[ "processed" ] = result[ "processed" ] + 1;
				result[ "notificationsCreated" ] =
					result[ "notificationsCreated" ] + notificationRows.len();
			} catch ( any exception ) {
				var failureRows = recordFailure(
					claimedEvent.id,
					workerId,
					maxAttempts,
					exception
				);
				if (
					failureRows.len()
					&& ( failureRows[ 1 ].is_failed ?: false )
				) {
					result[ "failed" ] = result[ "failed" ] + 1;
				} else if ( failureRows.len() ) {
					result[ "retried" ] = result[ "retried" ] + 1;
				}
			}
		}
		return result;
	}

	private array function recordFailure(
		required string eventId,
		required string workerId,
		required numeric maxAttempts,
		required any exception
	){
		var errorMessage = left(
			trim(
				arguments.exception.message
				& (
					( arguments.exception.detail ?: "" ).len()
						? " - " & arguments.exception.detail
						: ""
				)
			),
			4000
		);
		return queryExecute(
			"UPDATE outbox_event
			 SET claimed_at=NULL,
			     claimed_by=NULL,
			     last_error=:lastError,
			     failed_at=CASE
			         WHEN attempts>=CAST(:maxAttempts AS INTEGER) THEN now()
			         ELSE NULL
			     END,
			     available_at=CASE
			         WHEN attempts>=CAST(:maxAttempts AS INTEGER) THEN available_at
			         ELSE now()+make_interval(
			             secs => LEAST(
			                 3600,
			                 ROUND(5*POWER(2,GREATEST(attempts-1,0)))::INTEGER
			             )
			         )
			     END
			 WHERE id=CAST(:eventId AS UUID)
			   AND claimed_by=:workerId
			   AND processed_at IS NULL
			   AND failed_at IS NULL
			 RETURNING attempts,(failed_at IS NOT NULL) AS is_failed",
			{
				eventId=arguments.eventId,
				workerId=arguments.workerId,
				maxAttempts=arguments.maxAttempts,
				lastError=errorMessage
			},
			{ returntype="array" }
		);
	}

	private numeric function environmentInteger(
		required string name,
		required numeric fallback,
		required numeric minimum,
		required numeric maximum
	){
		return boundedInteger(
			variables.environment[ arguments.name ] ?: arguments.fallback,
			arguments.fallback,
			arguments.minimum,
			arguments.maximum
		);
	}

	private numeric function boundedInteger(
		required any value,
		required numeric fallback,
		required numeric minimum,
		required numeric maximum
	){
		if ( !isNumeric( arguments.value ) ) return arguments.fallback;
		var parsed = fix( val( arguments.value ) );
		if ( parsed < arguments.minimum || parsed > arguments.maximum ) {
			return arguments.fallback;
		}
		return parsed;
	}

	private string function canonicalUuid( required string value ){
		var compact = lCase( replace( arguments.value, "-", "", "all" ) );
		if ( !reFind( "^[0-9a-f]{32}$", compact ) ) {
			throw(
				type="OutboxProcessor.InvalidUuid",
				message="Could not generate a valid worker UUID."
			);
		}
		return left( compact, 8 )
			& "-" & mid( compact, 9, 4 )
			& "-" & mid( compact, 13, 4 )
			& "-" & mid( compact, 17, 4 )
			& "-" & right( compact, 12 );
	}

}
