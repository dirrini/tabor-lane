component singleton {

	property name="tokenService" inject="TokenService";
	property name="avatarService" inject="AvatarService";

	array function getUserWorkspaces( required string userId ){
		return queryExecute(
			"SELECT CAST(w.id AS TEXT) AS id,w.name,w.slug,w.plan,wm.role,
			        (w.id=u.last_workspace_id) AS is_last_workspace
			 FROM app_user u
			 JOIN workspace_member wm ON wm.user_id=u.id
			 JOIN workspace w ON w.id=wm.workspace_id
			 WHERE u.id=CAST(:userId AS UUID)
			 ORDER BY CASE WHEN w.id=u.last_workspace_id THEN 0 ELSE 1 END,
			          wm.created_at,w.name,w.id",
			{ userId=arguments.userId },
			{ returntype="array" }
		);
	}

	struct function activateWorkspace( required string userId, required string workspaceId ){
		var rows = queryExecute(
			"UPDATE app_user user_account
			 SET last_workspace_id=selection.workspace_id
			 FROM (
			    SELECT wm.user_id,wm.workspace_id,wm.role,w.name,w.plan
			    FROM workspace_member wm
			    JOIN workspace w ON w.id=wm.workspace_id
			    WHERE wm.user_id=CAST(:userId AS UUID)
			      AND wm.workspace_id=CAST(:workspaceId AS UUID)
			 ) selection
			 WHERE user_account.id=selection.user_id
			 RETURNING CAST(selection.workspace_id AS TEXT) AS workspace_id,
			           selection.name AS workspace_name,selection.role,selection.plan",
			{ userId=arguments.userId, workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		return rows.len()
			? {
				success=true,
				workspaceId=rows[ 1 ].workspace_id,
				workspaceName=rows[ 1 ].workspace_name,
				role=rows[ 1 ].role,
				plan=rows[ 1 ].plan
			}
			: { success=false, code="forbidden" };
	}

	array function getMembers( required string userId, required string workspaceId ){
		assertMember( arguments.userId, arguments.workspaceId );
		var members = queryExecute(
			"SELECT CAST(u.id AS TEXT) AS id, u.display_name, u.email, wm.role,
			        u.email_verified_at, wm.created_at,CAST(avatar.id AS TEXT) AS avatar_id
			 FROM workspace_member wm
			 JOIN app_user u ON u.id = wm.user_id
			 LEFT JOIN user_avatar avatar
			   ON avatar.user_id=u.id
			  AND avatar.status='available' AND avatar.deleted_at IS NULL
			 WHERE wm.workspace_id = CAST(:workspaceId AS UUID)
			 ORDER BY CASE wm.role WHEN 'owner' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END,
			          u.display_name",
			{ workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
		for ( var member in members ) {
			member.initials = avatarService.initials( member.display_name );
		}
		return members;
	}

	array function getPendingInvitations( required string userId, required string workspaceId ){
		assertMember( arguments.userId, arguments.workspaceId );
		return queryExecute(
			"SELECT CAST(id AS TEXT) AS id, invitee_name, email, role, expires_at, created_at
			 FROM workspace_invitation
			 WHERE workspace_id = CAST(:workspaceId AS UUID)
			   AND accepted_at IS NULL
			   AND expires_at > now()
			 ORDER BY created_at DESC",
			{ workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
	}

	struct function createInvitation(
		required string userId,
		required string workspaceId,
		required string inviteeName,
		required string email,
		string role = "member",
		string locale = "en_US"
	){
		var access = queryExecute(
			"SELECT w.name AS workspace_name, u.display_name AS inviter_name, wm.role
			 FROM workspace_member wm
			 JOIN workspace w ON w.id = wm.workspace_id
			 JOIN app_user u ON u.id = wm.user_id
			 WHERE wm.user_id = CAST(:userId AS UUID)
			   AND wm.workspace_id = CAST(:workspaceId AS UUID)",
			{ userId = arguments.userId, workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
		if ( !access.len() || !listFindNoCase( "owner,admin", access[ 1 ].role ) ) {
			return { success = false, code = "forbidden" };
		}
		if ( !listFindNoCase( "admin,member,viewer", arguments.role ) ) {
			return { success = false, code = "invalid_role" };
		}
		var normalizedName = trim( arguments.inviteeName );
		if ( !normalizedName.len() || normalizedName.len() > 160 ) {
			return { success = false, code = "invalid_name" };
		}

		var normalizedEmail = lCase( trim( arguments.email ) );
		var existing = queryExecute(
			"SELECT 1 FROM workspace_member wm
			 JOIN app_user u ON u.id = wm.user_id
			 WHERE wm.workspace_id = CAST(:workspaceId AS UUID) AND u.email = :email",
			{ workspaceId = arguments.workspaceId, email = normalizedEmail },
			{ returntype = "array" }
		);
		if ( existing.len() ) {
			return { success = false, code = "already_member" };
		}

		var token = tokenService.generateToken();
		transaction {
			queryExecute(
				"DELETE FROM workspace_invitation
				 WHERE workspace_id = CAST(:workspaceId AS UUID)
				   AND lower(email) = :email
				   AND accepted_at IS NULL",
				{ workspaceId = arguments.workspaceId, email = normalizedEmail }
			);
			queryExecute(
				"INSERT INTO workspace_invitation
				    (workspace_id, invitee_name, email, role, token_hash, invited_by, expires_at)
				 VALUES
				    (CAST(:workspaceId AS UUID), :inviteeName, :email, :role, :tokenHash,
				     CAST(:userId AS UUID), :expiresAt)",
				{
					workspaceId = arguments.workspaceId,
					inviteeName = normalizedName,
					email = normalizedEmail,
					role = arguments.role,
					tokenHash = tokenService.hashToken( token ),
					userId = arguments.userId,
					expiresAt = {
						value = dateAdd( "d", 7, now() ),
						sqltype = "timestamp"
					}
				}
			);
		}
		return {
			success = true,
			token = token,
			inviteeName = normalizedName,
			email = normalizedEmail,
			role = arguments.role,
			workspaceName = access[ 1 ].workspace_name,
			inviterName = access[ 1 ].inviter_name,
			locale = arguments.locale
		};
	}

	struct function inspectInvitation( required string token ){
		var rows = queryExecute(
			"SELECT i.invitee_name, i.email, i.role, CAST(i.workspace_id AS TEXT) AS workspace_id,
			        w.name AS workspace_name, u.display_name AS inviter_name
			 FROM workspace_invitation i
			 JOIN workspace w ON w.id = i.workspace_id
			 JOIN app_user u ON u.id = i.invited_by
			 WHERE i.token_hash = :tokenHash
			   AND i.accepted_at IS NULL
			   AND i.expires_at > now()",
			{ tokenHash = tokenService.hashToken( arguments.token ) },
			{ returntype = "array" }
		);
		return rows.len()
			? {
				found = true,
				inviteeName = rows[ 1 ].invitee_name ?: "",
				email = rows[ 1 ].email,
				role = rows[ 1 ].role,
				workspaceId = rows[ 1 ].workspace_id,
				workspaceName = rows[ 1 ].workspace_name,
				inviterName = rows[ 1 ].inviter_name
			}
			: { found = false };
	}

	struct function acceptInvitation(
		required string token,
		required string userId,
		required string userEmail
	){
		var outcome = { success = false, code = "invalid_invitation" };
		var tokenHash = tokenService.hashToken( arguments.token );
		var normalizedEmail = lCase( trim( arguments.userEmail ) );
		transaction {
			var invitations = queryExecute(
				"SELECT CAST(invitation.id AS TEXT) AS id,invitation.email,invitation.role,
				        CAST(invitation.workspace_id AS TEXT) AS workspace_id,
				        workspace.name AS workspace_name,user_account.email AS user_email
				 FROM workspace_invitation invitation
				 JOIN workspace ON workspace.id=invitation.workspace_id
				 JOIN app_user user_account ON user_account.id=CAST(:userId AS UUID)
				 WHERE invitation.token_hash=:tokenHash
				   AND invitation.accepted_at IS NULL
				   AND invitation.expires_at>now()
				 FOR UPDATE OF invitation",
				{
					userId = arguments.userId,
					tokenHash = tokenHash
				},
				{ returntype = "array" }
			);
			if (
				invitations.len()
				&& lCase( invitations[ 1 ].email ) == normalizedEmail
				&& lCase( invitations[ 1 ].user_email ) == normalizedEmail
			) {
				var invitation = invitations[ 1 ];
				var consumed = queryExecute(
					"UPDATE workspace_invitation
					 SET accepted_at=now()
					 WHERE id=CAST(:invitationId AS UUID)
					   AND accepted_at IS NULL
					   AND expires_at>now()
					 RETURNING id",
					{ invitationId = invitation.id },
					{ returntype = "array" }
				);
				if ( consumed.len() ) {
					queryExecute(
						"INSERT INTO workspace_member (workspace_id, user_id, role)
						 VALUES (CAST(:workspaceId AS UUID), CAST(:userId AS UUID), :role)
						 ON CONFLICT (workspace_id, user_id) DO NOTHING",
						{
							workspaceId = invitation.workspace_id,
							userId = arguments.userId,
							role = invitation.role
						}
					);
					var effectiveMembership = queryExecute(
						"SELECT role
						 FROM workspace_member
						 WHERE workspace_id=CAST(:workspaceId AS UUID)
						   AND user_id=CAST(:userId AS UUID)",
						{
							workspaceId = invitation.workspace_id,
							userId = arguments.userId
						},
						{ returntype = "array" }
					);
					if ( effectiveMembership.len() ) {
						queryExecute(
							"UPDATE app_user
							 SET last_workspace_id=CAST(:workspaceId AS UUID)
							 WHERE id=CAST(:userId AS UUID)",
							{
								workspaceId = invitation.workspace_id,
								userId = arguments.userId
							}
						);
						outcome = {
							success = true,
							workspaceId = invitation.workspace_id,
							workspaceName = invitation.workspace_name,
							role = effectiveMembership[ 1 ].role
						};
					}
				}
			}
		}
		return outcome;
	}

	private void function assertMember( required string userId, required string workspaceId ){
		var access = queryExecute(
			"SELECT 1 FROM workspace_member
			 WHERE user_id = CAST(:userId AS UUID)
			   AND workspace_id = CAST(:workspaceId AS UUID)",
			{ userId = arguments.userId, workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
		if ( !access.len() ) {
			throw( type = "Workspace.Forbidden", message = "Workspace access denied." );
		}
	}

}
