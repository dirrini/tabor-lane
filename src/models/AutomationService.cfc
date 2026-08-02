component singleton {

	variables.maxRules = 50;

	struct function getManagement( required string userId, required string workspaceId ){
		var access = workspaceAccess( arguments.userId, arguments.workspaceId );
		if ( !access.found ) return failure( "not_found" );

		var canManage = listFindNoCase( "owner,admin", access.role ) > 0;
		var rules = queryExecute(
			"SELECT CAST(rule.id AS TEXT) AS id,rule.name,rule.is_enabled,
			        rule.run_count,rule.last_triggered_at,rule.created_at,
			        CAST(rule.board_id AS TEXT) AS board_id,board.name AS board_name,
			        CAST(rule.target_column_id AS TEXT) AS column_id,lane.name AS column_name,
			        board.is_archived AS board_is_archived,lane.is_archived AS column_is_archived,
			        lane.is_hidden_from_members,
			        CAST(rule.recipient_user_id AS TEXT) AS recipient_user_id,
			        recipient.display_name AS recipient_name
			 FROM automation_rule rule
			 JOIN board ON board.id=rule.board_id AND board.workspace_id=rule.workspace_id
			 JOIN board_column lane ON lane.id=rule.target_column_id AND lane.board_id=rule.board_id
			 JOIN app_user recipient ON recipient.id=rule.recipient_user_id
			 WHERE rule.workspace_id=CAST(:workspaceId AS UUID)
			   AND rule.deleted_at IS NULL
			   AND (lane.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
			 ORDER BY rule.created_at,rule.id",
			{
				workspaceId=arguments.workspaceId,
				canViewHidden=canManage
			},
			{ returntype="array" }
		);

		var destinations = [];
		var members = [];
		if ( canManage ) {
			destinations = queryExecute(
				"SELECT CAST(board.id AS TEXT) AS board_id,board.name AS board_name,
				        CAST(lane.id AS TEXT) AS column_id,lane.name AS column_name,
				        lane.is_hidden_from_members
				 FROM board
				 JOIN board_column lane ON lane.board_id=board.id AND lane.is_archived=false
				 WHERE board.workspace_id=CAST(:workspaceId AS UUID)
				   AND board.is_archived=false
				 ORDER BY board.position,board.created_at,lane.position,lane.created_at",
				{ workspaceId=arguments.workspaceId },
				{ returntype="array" }
			);
			members = queryExecute(
				"SELECT CAST(member.user_id AS TEXT) AS id,app_user.display_name
				 FROM workspace_member member
				 JOIN app_user ON app_user.id=member.user_id
				 WHERE member.workspace_id=CAST(:workspaceId AS UUID)
				 ORDER BY lower(app_user.display_name),lower(app_user.email)",
				{ workspaceId=arguments.workspaceId },
				{ returntype="array" }
			);
		}

		return {
			found=true,
			code="ok",
			role=access.role,
			plan=access.plan,
			isPremium=compareNoCase( access.plan, "premium" ) == 0,
			canManage=canManage,
			canCreate=canManage
				&& compareNoCase( access.plan, "premium" ) == 0
				&& rules.len() < variables.maxRules,
			maxRules=variables.maxRules,
			rules=rules,
			destinations=destinations,
			members=members
		};
	}

	struct function createRule(
		required string userId,
		required string workspaceId,
		required string name,
		required string boardId,
		required string columnId,
		required string recipientUserId
	){
		var access = workspaceAccess( arguments.userId, arguments.workspaceId );
		if ( !canManage( access ) ) return failure( "forbidden" );
		if ( compareNoCase( access.plan, "premium" ) != 0 ) return failure( "plan_required" );

		var cleanName = trim( arguments.name );
		if (
			!cleanName.len() || cleanName.len() > 160
			|| !isCanonicalUuid( arguments.boardId )
			|| !isCanonicalUuid( arguments.columnId )
			|| !isCanonicalUuid( arguments.recipientUserId )
		) return failure( "invalid" );

		var outcome = failure( "generic" );
		try {
			transaction {
				// Serializes the workspace quota and plan check across concurrent writes.
				var workspaceLock = queryExecute(
					"SELECT plan
					 FROM workspace
					 WHERE id=CAST(:workspaceId AS UUID)
					 FOR UPDATE",
					{ workspaceId=arguments.workspaceId },
					{ returntype="array" }
				);
				if ( !workspaceLock.len() ) {
					outcome = failure( "not_found" );
				} else if ( compareNoCase( workspaceLock[ 1 ].plan, "premium" ) != 0 ) {
					outcome = failure( "plan_required" );
				} else {
					var ruleCount = queryExecute(
						"SELECT COUNT(*) AS total
						 FROM automation_rule
						 WHERE workspace_id=CAST(:workspaceId AS UUID) AND deleted_at IS NULL",
						{ workspaceId=arguments.workspaceId },
						{ returntype="array" }
					)[ 1 ].total;
					if ( val( ruleCount ) >= variables.maxRules ) {
						outcome = failure( "rule_limit" );
					} else {
						var validConfiguration = queryExecute(
							"SELECT 1
							 FROM board
							 JOIN board_column lane ON lane.board_id=board.id
							 JOIN workspace_member recipient
							   ON recipient.workspace_id=board.workspace_id
							  AND recipient.user_id=CAST(:recipientUserId AS UUID)
							 WHERE board.id=CAST(:boardId AS UUID)
							   AND board.workspace_id=CAST(:workspaceId AS UUID)
							   AND board.is_archived=false
							   AND lane.id=CAST(:columnId AS UUID)
							   AND lane.is_archived=false
							   AND (
							       lane.is_hidden_from_members=false
							       OR recipient.role IN ('owner','admin')
							   )",
							{
								workspaceId=arguments.workspaceId,
								boardId=arguments.boardId,
								columnId=arguments.columnId,
								recipientUserId=arguments.recipientUserId
							},
							{ returntype="array" }
						);
						if ( !validConfiguration.len() ) {
							outcome = failure( "invalid" );
						} else {
							var inserted = queryExecute(
								"INSERT INTO automation_rule(
								     workspace_id,board_id,target_column_id,recipient_user_id,name,created_by
								 )
								 VALUES(
								     CAST(:workspaceId AS UUID),CAST(:boardId AS UUID),CAST(:columnId AS UUID),
								     CAST(:recipientUserId AS UUID),:name,CAST(:userId AS UUID)
								 )
								 RETURNING CAST(id AS TEXT) AS id",
								{
									workspaceId=arguments.workspaceId,
									boardId=arguments.boardId,
									columnId=arguments.columnId,
									recipientUserId=arguments.recipientUserId,
									name=cleanName,
									userId=arguments.userId
								},
								{ returntype="array" }
							);
							outcome = success( inserted[ 1 ].id );
						}
					}
				}
			}
		} catch ( database exception ) {
			if ( ( exception.sqlState ?: "" ) == "23505" ) return failure( "duplicate" );
			rethrow;
		}
		return outcome;
	}

	struct function setEnabled(
		required string userId,
		required string workspaceId,
		required string ruleId,
		required boolean enabled
	){
		var access = workspaceAccess( arguments.userId, arguments.workspaceId );
		if ( !canManage( access ) ) return failure( "forbidden" );
		if ( !isCanonicalUuid( arguments.ruleId ) ) return failure( "not_found" );
		if ( arguments.enabled && compareNoCase( access.plan, "premium" ) != 0 ) {
			return failure( "plan_required" );
		}

		var updated = queryExecute(
			"UPDATE automation_rule rule
			 SET is_enabled=CAST(:enabled AS BOOLEAN),updated_at=now()
			 FROM board,board_column lane
			 WHERE rule.id=CAST(:ruleId AS UUID)
			   AND rule.workspace_id=CAST(:workspaceId AS UUID)
			   AND rule.deleted_at IS NULL
			   AND board.id=rule.board_id
			   AND lane.id=rule.target_column_id AND lane.board_id=rule.board_id
			   AND (
			       CAST(:enabled AS BOOLEAN)=false
			       OR (board.is_archived=false AND lane.is_archived=false)
			   )
			 RETURNING CAST(rule.id AS TEXT) AS id",
			{
				ruleId=arguments.ruleId,
				workspaceId=arguments.workspaceId,
				enabled=arguments.enabled
			},
			{ returntype="array" }
		);
		return updated.len() ? success( updated[ 1 ].id ) : failure( "not_found" );
	}

	struct function removeRule(
		required string userId,
		required string workspaceId,
		required string ruleId
	){
		var access = workspaceAccess( arguments.userId, arguments.workspaceId );
		if ( !canManage( access ) ) return failure( "forbidden" );
		if ( !isCanonicalUuid( arguments.ruleId ) ) return failure( "not_found" );

		var removed = queryExecute(
			"UPDATE automation_rule
			 SET is_enabled=false,deleted_at=now(),updated_at=now()
			 WHERE id=CAST(:ruleId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			   AND deleted_at IS NULL
			 RETURNING CAST(id AS TEXT) AS id",
			{ ruleId=arguments.ruleId,workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		return removed.len() ? success( removed[ 1 ].id ) : failure( "not_found" );
	}

	struct function expandRecipientsForClaimedEvent(
		required string eventId,
		required string workerId
	){
		if ( !isCanonicalUuid( arguments.eventId ) || !isCanonicalUuid( arguments.workerId ) ) {
			return failure( "not_found" );
		}

		var matches = queryExecute(
			"SELECT CAST(rule.id AS TEXT) AS rule_id,
			        CAST(rule.recipient_user_id AS TEXT) AS recipient_user_id,
			        event_record.recipient_user_ids
			 FROM outbox_event event_record
			 JOIN workspace ON workspace.id=event_record.workspace_id AND workspace.plan='premium'
			 JOIN card ON card.id=event_record.aggregate_id
			           AND card.workspace_id=event_record.workspace_id
			           AND card.archived_at IS NULL
			 JOIN automation_rule rule
			   ON rule.workspace_id=event_record.workspace_id
			  AND rule.board_id=card.board_id
			  AND rule.is_enabled=true
			  AND rule.deleted_at IS NULL
			 JOIN board ON board.id=rule.board_id
			           AND board.workspace_id=rule.workspace_id
			           AND board.is_archived=false
			 JOIN board_column lane ON lane.id=rule.target_column_id
			                       AND lane.board_id=rule.board_id
			                       AND lane.is_archived=false
			 JOIN workspace_member recipient
			   ON recipient.workspace_id=rule.workspace_id
			  AND recipient.user_id=rule.recipient_user_id
			 JOIN board_column current_lane
			   ON current_lane.id=card.column_id
			  AND current_lane.board_id=card.board_id
			  AND current_lane.is_archived=false
			  AND (
			      current_lane.is_hidden_from_members=false
			      OR recipient.role IN ('owner','admin')
			  )
			 CROSS JOIN LATERAL (
			     SELECT value AS to_column_id
			     FROM jsonb_each_text(event_record.payload)
			     WHERE lower(key)='tolaneid'
			     LIMIT 1
			 ) payload_lane
			 WHERE event_record.id=CAST(:eventId AS UUID)
			   AND event_record.claimed_by=:workerId
			   AND event_record.processed_at IS NULL
			   AND event_record.failed_at IS NULL
			   AND event_record.event_type='card.moved'
			   AND event_record.aggregate_type='card'
			   AND rule.created_at<=event_record.created_at
			   AND recipient.user_id IS DISTINCT FROM event_record.actor_id
			   AND lower(payload_lane.to_column_id)=lower(CAST(rule.target_column_id AS TEXT))
			 ORDER BY rule.created_at,rule.id
			 FOR UPDATE OF event_record,workspace,rule",
			{ eventId=arguments.eventId,workerId=arguments.workerId },
			{ returntype="array" }
		);
		if ( !matches.len() ) return { success=true,code="ok",matched=0 };

		var recipients = jsonArray( matches[ 1 ].recipient_user_ids );
		var knownRecipients = {};
		for ( var existingRecipient in recipients ) {
			knownRecipients[ lCase( toString( existingRecipient ) ) ] = true;
		}
		for ( var match in matches ) {
			var recipientId = lCase( match.recipient_user_id );
			if ( !structKeyExists( knownRecipients, recipientId ) ) {
				recipients.append( recipientId );
				knownRecipients[ recipientId ] = true;
			}
		}

		var eventUpdated = queryExecute(
			"UPDATE outbox_event
			 SET recipient_user_ids=CAST(:recipients AS JSONB)
			 WHERE id=CAST(:eventId AS UUID)
			   AND claimed_by=:workerId
			   AND processed_at IS NULL
			   AND failed_at IS NULL
			 RETURNING CAST(id AS TEXT) AS id",
			{
				eventId=arguments.eventId,
				workerId=arguments.workerId,
				recipients=serializeJSON( recipients )
			},
			{ returntype="array" }
		);
		if ( !eventUpdated.len() ) {
			throw(
				type="Automation.LostOutboxClaim",
				message="The automation could not expand recipients after losing the outbox claim."
			);
		}

		var executed = 0;
		for ( var matchedRule in matches ) {
			var execution = queryExecute(
				"INSERT INTO automation_execution(
				     automation_rule_id,event_id,workspace_id,recipient_user_id
				 )
				 SELECT rule.id,CAST(:eventId AS UUID),rule.workspace_id,rule.recipient_user_id
				 FROM automation_rule rule
				 WHERE rule.id=CAST(:ruleId AS UUID)
				   AND rule.is_enabled=true AND rule.deleted_at IS NULL
				 ON CONFLICT (automation_rule_id,event_id) DO NOTHING
				 RETURNING CAST(automation_rule_id AS TEXT) AS rule_id",
				{ eventId=arguments.eventId,ruleId=matchedRule.rule_id },
				{ returntype="array" }
			);
			if ( execution.len() ) {
				executed++;
				queryExecute(
					"UPDATE automation_rule
					 SET run_count=run_count+1,last_triggered_at=now(),updated_at=now()
					 WHERE id=CAST(:ruleId AS UUID)",
					{ ruleId=matchedRule.rule_id }
				);
			}
		}
		return { success=true,code="ok",matched=executed };
	}

	private struct function workspaceAccess( required string userId, required string workspaceId ){
		if ( !isCanonicalUuid( arguments.userId ) || !isCanonicalUuid( arguments.workspaceId ) ) {
			return { found=false };
		}
		var rows = queryExecute(
			"SELECT member.role,workspace.plan
			 FROM workspace_member member
			 JOIN workspace ON workspace.id=member.workspace_id
			 WHERE member.user_id=CAST(:userId AS UUID)
			   AND member.workspace_id=CAST(:workspaceId AS UUID)",
			{ userId=arguments.userId,workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		return rows.len()
			? { found=true,role=rows[ 1 ].role,plan=rows[ 1 ].plan }
			: { found=false };
	}

	private boolean function canManage( required struct access ){
		return ( arguments.access.found ?: false )
			&& listFindNoCase( "owner,admin", arguments.access.role ) > 0;
	}

	private struct function success( required string id ){
		return { success=true,code="ok",id=arguments.id };
	}

	private struct function failure( required string code ){
		return { success=false,code=arguments.code };
	}

	private array function jsonArray( required any value ){
		if ( isArray( arguments.value ) ) return duplicate( arguments.value );
		if ( isSimpleValue( arguments.value ) && isJSON( toString( arguments.value ) ) ) {
			var decoded = deserializeJSON( toString( arguments.value ) );
			return isArray( decoded ) ? decoded : [];
		}
		return [];
	}

	private boolean function isCanonicalUuid( required string value ){
		return reFindNoCase(
			"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
			trim( arguments.value )
		) > 0;
	}

}
