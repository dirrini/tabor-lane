component singleton {

	property name="passwordService" inject="PasswordService";
	property name="eventPublisherService" inject="EventPublisherService";

	struct function getSettings(
		required string userId,
		required string workspaceId
	){
		if ( !isCanonicalUuid( arguments.userId ) || !isCanonicalUuid( arguments.workspaceId ) ) {
			return { found=false };
		}

		var rows = queryExecute(
			"SELECT CAST(workspace_record.id AS TEXT) AS id,workspace_record.name,
			        workspace_record.slug,workspace_record.plan,workspace_record.timezone,
			        workspace_record.default_locale,workspace_record.invitation_policy,
			        workspace_record.board_creation_policy,workspace_record.created_at,
			        membership.role,user_account.password_hash IS NOT NULL AS has_password
			 FROM workspace workspace_record
			 JOIN workspace_member membership
			   ON membership.workspace_id=workspace_record.id
			  AND membership.user_id=CAST(:userId AS UUID)
			 JOIN app_user user_account ON user_account.id=membership.user_id
			 WHERE workspace_record.id=CAST(:workspaceId AS UUID)",
			{
				userId=arguments.userId,
				workspaceId=arguments.workspaceId
			},
			{ returntype="array" }
		);
		if ( !rows.len() ) return { found=false };

		var transferCandidates = [];
		if ( rows[ 1 ].role == "owner" ) {
			transferCandidates = queryExecute(
				"SELECT CAST(membership.user_id AS TEXT) AS id,user_account.display_name,
				        user_account.email,membership.role
				 FROM workspace_member membership
				 JOIN app_user user_account ON user_account.id=membership.user_id
				 WHERE membership.workspace_id=CAST(:workspaceId AS UUID)
				   AND membership.user_id<>CAST(:userId AS UUID)
				   AND membership.role<>'owner'
				   AND user_account.email_verified_at IS NOT NULL
				 ORDER BY CASE membership.role WHEN 'admin' THEN 1 WHEN 'member' THEN 2 ELSE 3 END,
				          user_account.display_name,user_account.id",
				{
					workspaceId=arguments.workspaceId,
					userId=arguments.userId
				},
				{ returntype="array" }
			);
		}

		return {
			found=true,
			settings=rows[ 1 ],
			role=rows[ 1 ].role,
			canEditGeneral=listFindNoCase( "owner,admin", rows[ 1 ].role ) > 0,
			canManageSecurity=rows[ 1 ].role == "owner",
			transferCandidates=transferCandidates,
			timezoneSuggestions=[
				"UTC",
				"America/Sao_Paulo",
				"America/Fortaleza",
				"America/Manaus",
				"America/New_York",
				"America/Chicago",
				"America/Denver",
				"America/Los_Angeles",
				"Europe/London",
				"Europe/Lisbon",
				"Europe/Madrid",
				"Europe/Paris",
				"Asia/Tokyo",
				"Asia/Singapore",
				"Australia/Sydney"
			]
		};
	}

	struct function updateGeneral(
		required string userId,
		required string workspaceId,
		required string name,
		required string slug,
		required string timezone,
		required string defaultLocale
	){
		var normalizedName = trim( arguments.name );
		var normalizedSlug = lCase( trim( arguments.slug ) );
		var normalizedTimezone = trim( arguments.timezone );
		var requestedLocale = trim( arguments.defaultLocale );
		var normalizedLocale = compareNoCase( requestedLocale, "pt_BR" ) == 0
			? "pt_BR"
			: ( compareNoCase( requestedLocale, "en_US" ) == 0 ? "en_US" : "" );
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !normalizedName.len()
			|| normalizedName.len() > 160
			|| normalizedSlug.len() < 3
			|| normalizedSlug.len() > 100
			|| !reFind( "^[a-z0-9]+(?:-[a-z0-9]+)*$", normalizedSlug )
			|| !normalizedLocale.len()
			|| !validTimezone( normalizedTimezone )
		) return failure( "invalid" );

		var outcome = failure( "forbidden" );
		try {
			transaction {
				var accessRows = queryExecute(
					"SELECT membership.role
					 FROM workspace workspace_record
					 JOIN workspace_member membership
					   ON membership.workspace_id=workspace_record.id
					  AND membership.user_id=CAST(:userId AS UUID)
					 WHERE workspace_record.id=CAST(:workspaceId AS UUID)
					 FOR UPDATE OF workspace_record,membership",
					{
						userId=arguments.userId,
						workspaceId=arguments.workspaceId
					},
					{ returntype="array" }
				);
				if ( accessRows.len() && listFindNoCase( "owner,admin", accessRows[ 1 ].role ) ) {
					queryExecute(
						"UPDATE workspace
						 SET name=:name,slug=:slug,timezone=:timezone,
						     default_locale=:defaultLocale,updated_at=now()
						 WHERE id=CAST(:workspaceId AS UUID)",
						{
							name=normalizedName,
							slug=normalizedSlug,
							timezone=normalizedTimezone,
							defaultLocale=normalizedLocale,
							workspaceId=arguments.workspaceId
						}
					);
					outcome = { success=true,code="ok",name=normalizedName };
				}
			}
		} catch ( database exception ) {
			if ( ( exception.sqlState ?: "" ) == "23505" ) return failure( "slug_taken" );
			rethrow;
		}
		return outcome;
	}

	struct function updateSecurity(
		required string userId,
		required string workspaceId,
		required string invitationPolicy,
		required string boardCreationPolicy
	){
		var invitationPolicy = lCase( trim( arguments.invitationPolicy ) );
		var boardCreationPolicy = lCase( trim( arguments.boardCreationPolicy ) );
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !listFindNoCase( "owner_admin,owner_only", invitationPolicy )
			|| !listFindNoCase( "owner_admin,owner_only", boardCreationPolicy )
		) return failure( "invalid" );

		var outcome = failure( "forbidden" );
		transaction {
			var accessRows = queryExecute(
				"SELECT membership.role
				 FROM workspace workspace_record
				 JOIN workspace_member membership
				   ON membership.workspace_id=workspace_record.id
				  AND membership.user_id=CAST(:userId AS UUID)
				 WHERE workspace_record.id=CAST(:workspaceId AS UUID)
				 FOR UPDATE OF workspace_record,membership",
				{
					userId=arguments.userId,
					workspaceId=arguments.workspaceId
				},
				{ returntype="array" }
			);
			if ( accessRows.len() && accessRows[ 1 ].role == "owner" ) {
				queryExecute(
					"UPDATE workspace
					 SET invitation_policy=:invitationPolicy,
					     board_creation_policy=:boardCreationPolicy,updated_at=now()
					 WHERE id=CAST(:workspaceId AS UUID)",
					{
						invitationPolicy=invitationPolicy,
						boardCreationPolicy=boardCreationPolicy,
						workspaceId=arguments.workspaceId
					}
				);
				outcome = { success=true,code="ok" };
			}
		}
		return outcome;
	}

	struct function transferOwnership(
		required string userId,
		required string workspaceId,
		required string targetUserId,
		required string currentPassword
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.targetUserId )
			|| arguments.userId == arguments.targetUserId
		) return failure( "invalid_target" );

		var outcome = failure( "forbidden" );
		var transferId = canonicalUuid( createUUID() );
		transaction {
			var ownerRows = queryExecute(
				"SELECT membership.role,workspace_record.name,user_account.password_hash
				 FROM workspace workspace_record
				 JOIN workspace_member membership
				   ON membership.workspace_id=workspace_record.id
				  AND membership.user_id=CAST(:userId AS UUID)
				 JOIN app_user user_account ON user_account.id=membership.user_id
				 WHERE workspace_record.id=CAST(:workspaceId AS UUID)
				 FOR UPDATE OF workspace_record,membership,user_account",
				{
					workspaceId=arguments.workspaceId,
					userId=arguments.userId
				},
				{ returntype="array" }
			);
			if ( ownerRows.len() && ownerRows[ 1 ].role == "owner" ) {
				if ( isNull( ownerRows[ 1 ].password_hash ) ) {
					outcome = failure( "password_required" );
				} else if (
					!passwordService.verifyPassword(
						arguments.currentPassword,
						ownerRows[ 1 ].password_hash
					)
				) {
					outcome = failure( "invalid_password" );
				} else {
					outcome = failure( "invalid_target" );
					var targetRows = queryExecute(
					"SELECT membership.role,user_account.display_name,user_account.email
					 FROM workspace_member membership
					 JOIN app_user user_account ON user_account.id=membership.user_id
					 WHERE membership.workspace_id=CAST(:workspaceId AS UUID)
					   AND membership.user_id=CAST(:targetUserId AS UUID)
					   AND membership.role<>'owner'
					   AND user_account.email_verified_at IS NOT NULL
					 FOR UPDATE OF membership",
					{
						workspaceId=arguments.workspaceId,
						targetUserId=arguments.targetUserId
					},
					{ returntype="array" }
				);
					if ( targetRows.len() ) {
					queryExecute(
						"UPDATE workspace_member SET role='admin'
						 WHERE workspace_id=CAST(:workspaceId AS UUID)
						   AND user_id=CAST(:userId AS UUID)",
						{ workspaceId=arguments.workspaceId,userId=arguments.userId }
					);
					queryExecute(
						"UPDATE workspace_member SET role='owner'
						 WHERE workspace_id=CAST(:workspaceId AS UUID)
						   AND user_id=CAST(:targetUserId AS UUID)",
						{ workspaceId=arguments.workspaceId,targetUserId=arguments.targetUserId }
					);

					var payload = {};
					payload[ "workspaceName" ] = ownerRows[ 1 ].name;
					payload[ "newOwnerName" ] = targetRows[ 1 ].display_name;
					payload[ "newOwnerEmail" ] = targetRows[ 1 ].email;
					eventPublisherService.publish(
						workspaceId=arguments.workspaceId,
						eventType="workspace.ownership_transferred",
						aggregateType="workspace",
						aggregateId=arguments.workspaceId,
						actorId=arguments.userId,
						recipientUserIds=[ arguments.targetUserId ],
						payload=payload,
						deduplicationKey="workspace.ownership_transferred:#transferId#"
					);
					outcome = {
						success=true,
						code="ok",
						newOwnerName=targetRows[ 1 ].display_name
					};
					}
				}
			}
		}
		return outcome;
	}

	private boolean function validTimezone( required string value ){
		if ( !arguments.value.len() || arguments.value.len() > 64 ) return false;
		try {
			createObject( "java", "java.time.ZoneId" ).of( arguments.value );
		} catch ( any exception ) {
			return false;
		}
		return queryExecute(
			"SELECT 1 FROM pg_timezone_names WHERE name=:timezone LIMIT 1",
			{ timezone=arguments.value },
			{ returntype="array" }
		).len() > 0;
	}

	private struct function failure( required string code ){
		return { success=false,code=arguments.code };
	}

	private boolean function isCanonicalUuid( required string value ){
		return reFindNoCase(
			"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
			trim( arguments.value )
		) > 0;
	}

	private string function canonicalUuid( required string value ){
		var compact = lCase( replace( arguments.value, "-", "", "all" ) );
		return left( compact, 8 )
			& "-" & mid( compact, 9, 4 )
			& "-" & mid( compact, 13, 4 )
			& "-" & mid( compact, 17, 4 )
			& "-" & right( compact, 12 );
	}

}
