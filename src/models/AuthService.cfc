component singleton {

	property name="passwordService" inject="PasswordService";
	property name="tokenService" inject="TokenService";

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
		var userId = lCase( createUUID() );
		var workspaceId = hasInvitation ? invitation.workspaceId : lCase( createUUID() );
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
			} else {
				provisionWorkspace(
					userId = userId,
					workspaceId = workspaceId,
					workspaceName = workspaceDisplayName,
					locale = arguments.locale
				);
			}
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
			 ORDER BY wm.created_at
			 LIMIT 1",
			{ email = lCase( trim( arguments.email ) ) },
			{ returntype = "array" }
		);

		if ( !users.len() || isNull( users[ 1 ].password_hash ) || !passwordService.verifyPassword( arguments.password, users[ 1 ].password_hash ) ) {
			return { success = false, code = "invalid_credentials" };
		}
		return { success = true, user = mapUser( users[ 1 ] ) };
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

	private void function provisionWorkspace(
		required string userId,
		required string workspaceId,
		required string workspaceName,
		required string locale
	){
		var boardId = lCase( createUUID() );
		var slugBase = reReplace( lCase( trim( arguments.workspaceName ) ), "[^a-z0-9]+", "-", "all" );
		slugBase = reReplace( slugBase, "^-|-$", "", "all" );
		if ( !slugBase.len() ) {
			slugBase = "workspace";
		}
		var workspaceSlug = left( slugBase, 80 ) & "-" & left( replace( arguments.workspaceId, "-", "", "all" ), 8 );
		var columnIds = [ lCase( createUUID() ), lCase( createUUID() ), lCase( createUUID() ), lCase( createUUID() ) ];
		var columnNames = arguments.locale == "pt_BR"
			? [ "Ideias", "A fazer", "Em andamento", "Concluído" ]
			: [ "Ideas", "To do", "In progress", "Done" ];

		queryExecute(
			"INSERT INTO workspace (id, name, slug, plan)
			 VALUES (CAST(:id AS UUID), :name, :slug, 'free')",
			{ id = arguments.workspaceId, name = trim( arguments.workspaceName ), slug = workspaceSlug }
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
				"INSERT INTO board_column (id, board_id, name, position, wip_limit)
				 VALUES (CAST(:id AS UUID), CAST(:boardId AS UUID), :name, CAST(:position AS NUMERIC), :wipLimit)",
				{
					id = columnIds[ index ],
					boardId = boardId,
					name = columnNames[ index ],
					position = index,
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

	private boolean function emailExists( required string email ){
		var result = queryExecute(
			"SELECT EXISTS(SELECT 1 FROM app_user WHERE email = :email) AS found",
			{ email = arguments.email },
			{ returntype = "array" }
		);
		return result[ 1 ].found;
	}

}
