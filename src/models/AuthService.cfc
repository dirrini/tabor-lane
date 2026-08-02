component singleton {

	property name="passwordService" inject="PasswordService";
	property name="tokenService" inject="TokenService";
	property name="eventPublisherService" inject="EventPublisherService";

	struct function register(
		required string displayName,
		required string email,
		required string password,
		string workspaceName = "",
		string locale = "en_US",
		string invitationToken = ""
	){
		var normalizedEmail = lCase( trim( arguments.email ) );
		if ( emailExists( normalizedEmail ) ) {
			return { success = false, code = "email_exists" };
		}

		var invitation = {};
		if ( arguments.invitationToken.len() ) {
			invitation = findInvitation( arguments.invitationToken );
			if ( !invitation.found || invitation.email != normalizedEmail ) {
				return { success = false, code = "invalid_invitation" };
			}
		} else if ( !trim( arguments.workspaceName ).len() ) {
			return { success = false, code = "workspace_required" };
		}

		var hasInvitation = invitation.found ?: false;
		var userId = canonicalUuid( createUUID() );
		var workspaceId = hasInvitation ? invitation.workspaceId : canonicalUuid( createUUID() );
		var workspaceDisplayName = hasInvitation ? invitation.workspaceName : trim( arguments.workspaceName );
		var workspaceRole = hasInvitation ? invitation.role : "owner";

		transaction {
			queryExecute(
				"INSERT INTO app_user (id, email, display_name, password_hash, locale)
				 VALUES (CAST(:id AS UUID), :email, :displayName, :passwordHash, :locale)",
				{
					id = userId,
					email = normalizedEmail,
					displayName = trim( arguments.displayName ),
					passwordHash = passwordService.hashPassword( arguments.password ),
					locale = arguments.locale
				}
			);

			if ( hasInvitation ) {
				queryExecute(
					"INSERT INTO workspace_member (workspace_id, user_id, role)
					 VALUES (CAST(:workspaceId AS UUID), CAST(:userId AS UUID), :role)",
					{
						workspaceId = workspaceId,
						userId = userId,
						role = workspaceRole
					}
				);
				queryExecute(
					"UPDATE workspace_invitation
					 SET accepted_at = now()
					 WHERE id = CAST(:invitationId AS UUID)",
					{ invitationId = invitation.id }
				);
				publishMemberJoined(
					workspaceId=workspaceId,
					workspaceName=workspaceDisplayName,
					userId=userId,
					email=normalizedEmail,
					displayName=trim( arguments.displayName ),
					role=workspaceRole,
					invitationId=invitation.id
				);
			} else {
				provisionWorkspace(
					userId = userId,
					workspaceId = workspaceId,
					workspaceName = workspaceDisplayName,
					locale = arguments.locale
				);
			}
			queryExecute(
				"UPDATE app_user
				 SET last_workspace_id=CAST(:workspaceId AS UUID)
				 WHERE id=CAST(:userId AS UUID)",
				{ workspaceId=workspaceId, userId=userId }
			);
		}

		var user = {
			id = userId,
			email = normalizedEmail,
			displayName = trim( arguments.displayName ),
			workspaceId = workspaceId,
			workspaceName = workspaceDisplayName,
			role = workspaceRole,
			locale = arguments.locale,
			emailVerified = false
		};
		return {
			success = true,
			user = user,
			verificationToken = tokenService.createAuthToken(
				userId = userId,
				purpose = "email_verification",
				lifetimeMinutes = 1440
			)
		};
	}

	struct function authenticate( required string email, required string password ){
		var users = queryExecute(
			"SELECT CAST(u.id AS TEXT) AS id, u.email, u.display_name, u.password_hash, u.locale,
			        (u.email_verified_at IS NOT NULL) AS email_verified,
			        CAST(w.id AS TEXT) AS workspace_id, w.name AS workspace_name, wm.role
			 FROM app_user u
			 JOIN workspace_member wm ON wm.user_id = u.id
			 JOIN workspace w ON w.id = wm.workspace_id
			 WHERE u.email = :email
			 ORDER BY CASE WHEN w.id=u.last_workspace_id THEN 0 ELSE 1 END,
			          wm.created_at,w.id
			 LIMIT 1",
			{ email = lCase( trim( arguments.email ) ) },
			{ returntype = "array" }
		);

		if ( !users.len() || isNull( users[ 1 ].password_hash ) || !passwordService.verifyPassword( arguments.password, users[ 1 ].password_hash ) ) {
			return { success = false, code = "invalid_credentials" };
		}
		return { success = true, user = mapUser( users[ 1 ] ) };
	}

	struct function authenticateExternal(
		required string provider,
		required string subject,
		required string email
	){
		var normalizedEmail = lCase( trim( arguments.email ) );
		var identities = queryExecute(
			"SELECT CAST(u.id AS TEXT) AS id, u.email, u.display_name, u.locale,
			        (u.email_verified_at IS NOT NULL) AS email_verified,
			        CAST(w.id AS TEXT) AS workspace_id, w.name AS workspace_name, wm.role
			 FROM external_identity ei
			 JOIN app_user u ON u.id = ei.user_id
			 JOIN workspace_member wm ON wm.user_id = u.id
			 JOIN workspace w ON w.id = wm.workspace_id
			 WHERE ei.provider = :provider
			   AND ei.provider_subject = :subject
			 ORDER BY CASE WHEN w.id=u.last_workspace_id THEN 0 ELSE 1 END,
			          wm.created_at,w.id
			 LIMIT 1",
			{ provider = arguments.provider, subject = arguments.subject },
			{ returntype = "array" }
		);
		if ( identities.len() ) {
			queryExecute(
				"UPDATE external_identity
				 SET provider_email = :email, last_login_at = now()
				 WHERE provider = :provider AND provider_subject = :subject",
				{
					email = normalizedEmail,
					provider = arguments.provider,
					subject = arguments.subject
				}
			);
			return { success = true, user = mapUser( identities[ 1 ] ) };
		}

		var users = queryExecute(
			"SELECT CAST(id AS TEXT) AS id
			 FROM app_user
			 WHERE email = :email",
			{ email = normalizedEmail },
			{ returntype = "array" }
		);
		if ( !users.len() ) {
			return { success = false, needsRegistration = true };
		}

		var linked = false;
		transaction {
			queryExecute(
				"INSERT INTO external_identity (user_id, provider, provider_subject, provider_email)
				 VALUES (CAST(:userId AS UUID), :provider, :subject, :email)
				 ON CONFLICT DO NOTHING",
				{
					userId = users[ 1 ].id,
					provider = arguments.provider,
					subject = arguments.subject,
					email = normalizedEmail
				}
			);
			var matchingIdentity = queryExecute(
				"SELECT EXISTS(
				    SELECT 1 FROM external_identity
				    WHERE user_id = CAST(:userId AS UUID)
				      AND provider = :provider
				      AND provider_subject = :subject
				 ) AS found",
				{
					userId = users[ 1 ].id,
					provider = arguments.provider,
					subject = arguments.subject
				},
				{ returntype = "array" }
			);
			linked = matchingIdentity[ 1 ].found;
			if ( linked ) {
				queryExecute(
					"UPDATE app_user
					 SET email_verified_at = COALESCE(email_verified_at, now()), updated_at = now()
					 WHERE id = CAST(:userId AS UUID)",
					{ userId = users[ 1 ].id }
				);
			}
		}
		if ( !linked ) {
			return { success = false, code = "identity_conflict" };
		}
		return { success = true, user = loadUser( users[ 1 ].id ) };
	}

	struct function resolveWorkspaceContext(
		required string userId,
		string currentWorkspaceId = ""
	){
		var rows = queryExecute(
			"SELECT CAST(w.id AS TEXT) AS workspace_id,w.name AS workspace_name,wm.role,w.plan,
			        (w.id=u.last_workspace_id) AS is_last_workspace
			 FROM app_user u
			 JOIN workspace_member wm ON wm.user_id=u.id
			 JOIN workspace w ON w.id=wm.workspace_id
			 WHERE u.id=CAST(:userId AS UUID)
			 ORDER BY
			   CASE
			     WHEN :currentWorkspaceId<>'' AND CAST(w.id AS TEXT)=:currentWorkspaceId THEN 0
			     WHEN w.id=u.last_workspace_id THEN 1
			     ELSE 2
			   END,
			   wm.created_at,w.id
			 LIMIT 1",
			{
				userId=arguments.userId,
				currentWorkspaceId=trim( arguments.currentWorkspaceId )
			},
			{ returntype="array" }
		);
		if ( !rows.len() ) return { found=false };

		var selected = rows[ 1 ];
		if ( !selected.is_last_workspace ) {
			queryExecute(
				"UPDATE app_user
				 SET last_workspace_id=CAST(:workspaceId AS UUID)
				 WHERE id=CAST(:userId AS UUID)
				   AND last_workspace_id IS DISTINCT FROM CAST(:workspaceId AS UUID)",
				{
					workspaceId=selected.workspace_id,
					userId=arguments.userId
				}
			);
		}
		return {
			found=true,
			workspaceId=selected.workspace_id,
			workspaceName=selected.workspace_name,
			role=selected.role,
			plan=selected.plan
		};
	}

	struct function registerExternal(
		required string provider,
		required string subject,
		required string email,
		required string displayName,
		required string workspaceName,
		string locale = "en_US",
		string invitationToken = ""
	){
		var normalizedEmail = lCase( trim( arguments.email ) );
		var existing = authenticateExternal(
			provider = arguments.provider,
			subject = arguments.subject,
			email = normalizedEmail
		);
		if ( existing.success ) {
			return existing;
		}
		if ( !( existing.needsRegistration ?: false ) ) {
			return existing;
		}

		var invitation = {};
		if ( arguments.invitationToken.len() ) {
			invitation = findInvitation( arguments.invitationToken );
			if ( !invitation.found || invitation.email != normalizedEmail ) {
				return { success = false, code = "invalid_invitation" };
			}
		} else if ( !trim( arguments.workspaceName ).len() ) {
			return { success = false, code = "workspace_required" };
		}

		var hasInvitation = invitation.found ?: false;
		var userId = canonicalUuid( createUUID() );
		var workspaceId = hasInvitation ? invitation.workspaceId : canonicalUuid( createUUID() );
		var workspaceDisplayName = hasInvitation ? invitation.workspaceName : trim( arguments.workspaceName );
		var workspaceRole = hasInvitation ? invitation.role : "owner";

		try {
			transaction {
				queryExecute(
					"INSERT INTO app_user (id, email, display_name, password_hash, locale, email_verified_at)
					 VALUES (CAST(:id AS UUID), :email, :displayName, NULL, :locale, now())",
					{
						id = userId,
						email = normalizedEmail,
						displayName = trim( arguments.displayName ),
						locale = arguments.locale
					}
				);
				queryExecute(
					"INSERT INTO external_identity (user_id, provider, provider_subject, provider_email)
					 VALUES (CAST(:userId AS UUID), :provider, :subject, :email)",
					{
						userId = userId,
						provider = arguments.provider,
						subject = arguments.subject,
						email = normalizedEmail
					}
				);

				if ( hasInvitation ) {
					queryExecute(
						"INSERT INTO workspace_member (workspace_id, user_id, role)
						 VALUES (CAST(:workspaceId AS UUID), CAST(:userId AS UUID), :role)",
						{
							workspaceId = workspaceId,
							userId = userId,
							role = workspaceRole
						}
					);
					queryExecute(
						"UPDATE workspace_invitation SET accepted_at = now()
						 WHERE id = CAST(:invitationId AS UUID)",
						{ invitationId = invitation.id }
					);
					publishMemberJoined(
						workspaceId=workspaceId,
						workspaceName=workspaceDisplayName,
						userId=userId,
						email=normalizedEmail,
						displayName=trim( arguments.displayName ),
						role=workspaceRole,
						invitationId=invitation.id
					);
				} else {
					provisionWorkspace(
						userId = userId,
						workspaceId = workspaceId,
						workspaceName = workspaceDisplayName,
						locale = arguments.locale
					);
				}
				queryExecute(
					"UPDATE app_user
					 SET last_workspace_id=CAST(:workspaceId AS UUID)
					 WHERE id=CAST(:userId AS UUID)",
					{ workspaceId=workspaceId, userId=userId }
				);
			}
		} catch ( database exception ) {
			var raced = authenticateExternal(
				provider = arguments.provider,
				subject = arguments.subject,
				email = normalizedEmail
			);
			return raced.success ? raced : { success = false, code = "registration_failed" };
		}

		return {
			success = true,
			user = {
				id = userId,
				email = normalizedEmail,
				displayName = trim( arguments.displayName ),
				workspaceId = workspaceId,
				workspaceName = workspaceDisplayName,
				role = workspaceRole,
				locale = arguments.locale,
				emailVerified = true
			}
		};
	}

	struct function verifyEmail( required string token ){
		var consumed = tokenService.consumeAuthToken( arguments.token, "email_verification" );
		if ( !consumed.success ) {
			return consumed;
		}
		queryExecute(
			"UPDATE app_user SET email_verified_at = COALESCE(email_verified_at, now()) WHERE id = CAST(:userId AS UUID)",
			{ userId = consumed.userId }
		);
		return { success = true, userId = consumed.userId };
	}

	struct function createVerificationToken( required string userId ){
		var users = queryExecute(
			"SELECT (email_verified_at IS NOT NULL) AS email_verified
			 FROM app_user WHERE id = CAST(:userId AS UUID)",
			{ userId = arguments.userId },
			{ returntype = "array" }
		);
		if ( !users.len() || users[ 1 ].email_verified ) {
			return { success = false };
		}
		return {
			success = true,
			token = tokenService.createAuthToken( arguments.userId, "email_verification", 1440 )
		};
	}

	boolean function isEmailVerified( required string userId ){
		var users = queryExecute(
			"SELECT (email_verified_at IS NOT NULL) AS email_verified
			 FROM app_user WHERE id = CAST(:userId AS UUID)",
			{ userId = arguments.userId },
			{ returntype = "array" }
		);
		return users.len() && users[ 1 ].email_verified;
	}

	struct function requestPasswordReset( required string email ){
		var users = queryExecute(
			"SELECT CAST(id AS TEXT) AS id, email, display_name, locale
			 FROM app_user WHERE email = :email",
			{ email = lCase( trim( arguments.email ) ) },
			{ returntype = "array" }
		);
		if ( !users.len() ) {
			return { success = true, found = false };
		}
		return {
			success = true,
			found = true,
			user = {
				id = users[ 1 ].id,
				email = users[ 1 ].email,
				displayName = users[ 1 ].display_name,
				locale = users[ 1 ].locale
			},
			token = tokenService.createAuthToken( users[ 1 ].id, "password_reset", 30 )
		};
	}

	struct function resetPassword( required string token, required string password ){
		var consumed = tokenService.consumeAuthToken( arguments.token, "password_reset" );
		if ( !consumed.success ) {
			return consumed;
		}
		queryExecute(
			"UPDATE app_user
			 SET password_hash = :passwordHash, updated_at = now()
			 WHERE id = CAST(:userId AS UUID)",
			{
				passwordHash = passwordService.hashPassword( arguments.password ),
				userId = consumed.userId
			}
		);
		return { success = true };
	}

	struct function getProfile( required string userId, required string workspaceId ){
		var rows = queryExecute(
			"SELECT CAST(u.id AS TEXT) AS id, u.email, u.display_name, u.locale,
			        u.created_at, u.updated_at, u.password_hash IS NOT NULL AS has_password,
			        u.email_verified_at,
			        CAST(w.id AS TEXT) AS workspace_id, w.name AS workspace_name,
			        w.slug AS workspace_slug, w.created_at AS workspace_created_at,
			        w.plan, wm.role, wm.created_at AS member_since
			 FROM app_user u
			 JOIN workspace_member wm ON wm.user_id = u.id
			 JOIN workspace w ON w.id = wm.workspace_id
			 WHERE u.id = CAST(:userId AS UUID)
			   AND w.id = CAST(:workspaceId AS UUID)",
			{ userId = arguments.userId, workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
		return rows.len() ? { found = true, data = rows[ 1 ] } : { found = false };
	}

	struct function updateProfile(
		required string userId,
		required string displayName,
		required string email,
		required string locale
	){
		var normalizedEmail = lCase( trim( arguments.email ) );
		var normalizedName = trim( arguments.displayName );
		var requestedLocale = trim( arguments.locale );
		var normalizedLocale = compareNoCase( requestedLocale, "pt_BR" ) == 0
			? "pt_BR"
			: ( compareNoCase( requestedLocale, "en_US" ) == 0 ? "en_US" : "" );
		if (
			!normalizedName.len()
			|| !isValid( "email", normalizedEmail )
			|| !normalizedLocale.len()
		) {
			return { success = false, code = "invalid" };
		}
		var current = queryExecute(
			"SELECT email FROM app_user WHERE id = CAST(:userId AS UUID)",
			{ userId = arguments.userId },
			{ returntype = "array" }
		);
		if ( !current.len() ) return { success = false, code = "not_found" };
		var emailChanged = lCase( current[ 1 ].email ) != normalizedEmail;
		if ( emailChanged && emailExists( normalizedEmail ) ) {
			return { success = false, code = "email_exists" };
		}
		queryExecute(
			"UPDATE app_user
			 SET display_name = :displayName,
			     email = :email,
			     locale = :locale,
			     email_verified_at = CASE WHEN CAST(:emailChanged AS BOOLEAN) THEN NULL ELSE email_verified_at END,
			     updated_at = now()
			 WHERE id = CAST(:userId AS UUID)",
			{
				displayName = normalizedName,
				email = normalizedEmail,
				locale = normalizedLocale,
				emailChanged = emailChanged,
				userId = arguments.userId
			}
		);
		return {
			success = true,
			emailChanged = emailChanged,
			user = {
				id = arguments.userId,
				email = normalizedEmail,
				displayName = normalizedName,
				locale = normalizedLocale,
				emailVerified = !emailChanged
			},
			verificationToken = emailChanged
				? tokenService.createAuthToken( arguments.userId, "email_verification", 1440 )
				: ""
		};
	}

	struct function changePassword(
		required string userId,
		required string currentPassword,
		required string newPassword
	){
		if ( arguments.newPassword.len() < 10 ) {
			return { success = false, code = "password" };
		}
		var users = queryExecute(
			"SELECT password_hash FROM app_user WHERE id = CAST(:userId AS UUID)",
			{ userId = arguments.userId },
			{ returntype = "array" }
		);
		if ( !users.len() ) return { success = false, code = "not_found" };
		if (
			!isNull( users[ 1 ].password_hash )
			&& !passwordService.verifyPassword( arguments.currentPassword, users[ 1 ].password_hash )
		) {
			return { success = false, code = "current_password" };
		}
		queryExecute(
			"UPDATE app_user SET password_hash = :passwordHash, updated_at = now()
			 WHERE id = CAST(:userId AS UUID)",
			{
				passwordHash = passwordService.hashPassword( arguments.newPassword ),
				userId = arguments.userId
			}
		);
		return { success = true };
	}

	private void function provisionWorkspace(
		required string userId,
		required string workspaceId,
		required string workspaceName,
		required string locale
	){
		var boardId = canonicalUuid( createUUID() );
		var slugBase = reReplace( lCase( trim( arguments.workspaceName ) ), "[^a-z0-9]+", "-", "all" );
		slugBase = reReplace( slugBase, "^-|-$", "", "all" );
		if ( !slugBase.len() ) {
			slugBase = "workspace";
		}
		var workspaceSlug = left( slugBase, 80 ) & "-" & left( replace( arguments.workspaceId, "-", "", "all" ), 8 );
		var columnIds = [
			canonicalUuid( createUUID() ),
			canonicalUuid( createUUID() ),
			canonicalUuid( createUUID() ),
			canonicalUuid( createUUID() )
		];
		var columnNames = arguments.locale == "pt_BR"
			? [ "Ideias", "A fazer", "Em andamento", "Concluído" ]
			: [ "Ideas", "To do", "In progress", "Done" ];

		queryExecute(
			"INSERT INTO workspace (id, name, slug, plan, default_locale)
			 VALUES (CAST(:id AS UUID), :name, :slug, 'free', :defaultLocale)",
			{
				id = arguments.workspaceId,
				name = trim( arguments.workspaceName ),
				slug = workspaceSlug,
				defaultLocale = arguments.locale
			}
		);
		queryExecute(
			"INSERT INTO workspace_member (workspace_id, user_id, role)
			 VALUES (CAST(:workspaceId AS UUID), CAST(:userId AS UUID), 'owner')",
			{ workspaceId = arguments.workspaceId, userId = arguments.userId }
		);
		queryExecute(
			"INSERT INTO board (id, workspace_id, name, description)
			 VALUES (CAST(:id AS UUID), CAST(:workspaceId AS UUID), :name, :description)",
			{
				id = boardId,
				workspaceId = arguments.workspaceId,
				name = arguments.locale == "pt_BR" ? "Meu primeiro quadro" : "My first board",
				description = arguments.locale == "pt_BR" ? "Seu fluxo começa aqui." : "Your workflow starts here."
			}
		);
		for ( var index = 1; index <= columnIds.len(); index++ ) {
			queryExecute(
				"INSERT INTO board_column (id, board_id, name, position, wip_limit, is_completion_lane)
				 VALUES (CAST(:id AS UUID), CAST(:boardId AS UUID), :name, CAST(:position AS NUMERIC),
				         :wipLimit, CAST(:isCompletion AS BOOLEAN))",
				{
					id = columnIds[ index ],
					boardId = boardId,
					name = columnNames[ index ],
					position = index,
					isCompletion = index == columnIds.len(),
					wipLimit = {
						value = index == 3 ? 3 : "",
						null = index != 3,
						sqltype = "integer"
					}
				}
			);
		}
		queryExecute(
			"INSERT INTO card (workspace_id, board_id, column_id, title, description, position)
			 VALUES
			 (CAST(:workspaceId AS UUID), CAST(:boardId AS UUID), CAST(:columnOne AS UUID), :titleOne, :descriptionOne, 1),
			 (CAST(:workspaceId AS UUID), CAST(:boardId AS UUID), CAST(:columnTwo AS UUID), :titleTwo, :descriptionTwo, 1)",
			{
				workspaceId = arguments.workspaceId,
				boardId = boardId,
				columnOne = columnIds[ 1 ],
				columnTwo = columnIds[ 2 ],
				titleOne = arguments.locale == "pt_BR" ? "Conheça seu quadro" : "Explore your board",
				descriptionOne = arguments.locale == "pt_BR" ? "Crie, organize e mova cards entre as etapas." : "Create, organize and move cards through each stage.",
				titleTwo = arguments.locale == "pt_BR" ? "Crie seu primeiro processo" : "Build your first workflow",
				descriptionTwo = arguments.locale == "pt_BR" ? "Adapte as etapas à forma como sua equipe trabalha." : "Adapt each stage to how your team works."
			}
		);
	}

	private struct function findInvitation( required string token ){
		var rows = queryExecute(
			"SELECT CAST(i.id AS TEXT) AS id, i.email, i.role,
			        CAST(i.workspace_id AS TEXT) AS workspace_id, w.name AS workspace_name
			 FROM workspace_invitation i
			 JOIN workspace w ON w.id = i.workspace_id
			 WHERE i.token_hash = :tokenHash
			   AND i.accepted_at IS NULL
			   AND i.expires_at > now()",
			{ tokenHash = tokenService.hashToken( arguments.token ) },
			{ returntype = "array" }
		);
		return rows.len()
			? {
				found = true,
				id = rows[ 1 ].id,
				email = lCase( rows[ 1 ].email ),
				role = rows[ 1 ].role,
				workspaceId = rows[ 1 ].workspace_id,
				workspaceName = rows[ 1 ].workspace_name
			}
			: { found = false };
	}

	private void function publishMemberJoined(
		required string workspaceId,
		required string workspaceName,
		required string userId,
		required string email,
		required string displayName,
		required string role,
		required string invitationId
	){
		var recipientRows = queryExecute(
			"SELECT CAST(user_id AS TEXT) AS user_id
			 FROM workspace_member
			 WHERE workspace_id=CAST(:workspaceId AS UUID)
			   AND role IN ('owner','admin')
			   AND user_id<>CAST(:userId AS UUID)
			 ORDER BY created_at,user_id",
			{
				workspaceId=arguments.workspaceId,
				userId=arguments.userId
			},
			{ returntype="array" }
		);
		var recipients = [];
		for ( var recipientRow in recipientRows ) {
			recipients.append( recipientRow.user_id );
		}
		var payload = {};
		payload[ "workspaceName" ] = arguments.workspaceName;
		payload[ "memberId" ] = arguments.userId;
		payload[ "memberEmail" ] = arguments.email;
		payload[ "memberName" ] = arguments.displayName;
		payload[ "memberRole" ] = arguments.role;
		payload[ "invitationId" ] = arguments.invitationId;
		eventPublisherService.publish(
			workspaceId=arguments.workspaceId,
			eventType="workspace.member_joined",
			aggregateType="workspace",
			aggregateId=arguments.workspaceId,
			actorId=arguments.userId,
			recipientUserIds=recipients,
			payload=payload,
			deduplicationKey="workspace.member_joined:#arguments.invitationId#"
		);
	}

	private struct function mapUser( required struct row ){
		return {
			id = arguments.row.id,
			email = arguments.row.email,
			displayName = arguments.row.display_name,
			workspaceId = arguments.row.workspace_id,
			workspaceName = arguments.row.workspace_name,
			role = arguments.row.role,
			locale = arguments.row.locale,
			emailVerified = arguments.row.email_verified
		};
	}

	private struct function loadUser( required string userId ){
		var users = queryExecute(
			"SELECT CAST(u.id AS TEXT) AS id, u.email, u.display_name, u.locale,
			        (u.email_verified_at IS NOT NULL) AS email_verified,
			        CAST(w.id AS TEXT) AS workspace_id, w.name AS workspace_name, wm.role
			 FROM app_user u
			 JOIN workspace_member wm ON wm.user_id = u.id
			 JOIN workspace w ON w.id = wm.workspace_id
			 WHERE u.id = CAST(:userId AS UUID)
			 ORDER BY CASE WHEN w.id=u.last_workspace_id THEN 0 ELSE 1 END,
			          wm.created_at,w.id
			 LIMIT 1",
			{ userId = arguments.userId },
			{ returntype = "array" }
		);
		return users.len() ? mapUser( users[ 1 ] ) : {};
	}

	private boolean function emailExists( required string email ){
		var result = queryExecute(
			"SELECT EXISTS(SELECT 1 FROM app_user WHERE email = :email) AS found",
			{ email = arguments.email },
			{ returntype = "array" }
		);
		return result[ 1 ].found;
	}

	private string function canonicalUuid( required string value ){
		var compact = lCase( replace( arguments.value, "-", "", "all" ) );
		if ( !reFind( "^[0-9a-f]{32}$", compact ) ) {
			throw( type="Auth.InvalidUuid", message="Could not generate a valid UUID." );
		}
		return left( compact, 8 )
			& "-" & mid( compact, 9, 4 )
			& "-" & mid( compact, 13, 4 )
			& "-" & mid( compact, 17, 4 )
			& "-" & right( compact, 12 );
	}

}
