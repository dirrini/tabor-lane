component singleton {

	property name="tokenService" inject="TokenService";

	array function getMembers( required string userId, required string workspaceId ){
		assertMember( arguments.userId, arguments.workspaceId );
		return queryExecute(
			"SELECT CAST(u.id AS TEXT) AS id, u.display_name, u.email, wm.role,
			        u.email_verified_at, wm.created_at
			 FROM workspace_member wm
			 JOIN app_user u ON u.id = wm.user_id
			 WHERE wm.workspace_id = CAST(:workspaceId AS UUID)
			 ORDER BY CASE wm.role WHEN 'owner' THEN 1 WHEN 'admin' THEN 2 ELSE 3 END,
			          u.display_name",
			{ workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
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
		var invitation = inspectInvitation( arguments.token );
		if ( !invitation.found || lCase( invitation.email ) != lCase( arguments.userEmail ) ) {
			return { success = false, code = "invalid_invitation" };
		}
		transaction {
			queryExecute(
				"INSERT INTO workspace_member (workspace_id, user_id, role)
				 VALUES (CAST(:workspaceId AS UUID), CAST(:userId AS UUID), :role)
				 ON CONFLICT (workspace_id, user_id) DO NOTHING",
				{
					workspaceId = invitation.workspaceId,
					userId = arguments.userId,
					role = invitation.role
				}
			);
			queryExecute(
				"UPDATE workspace_invitation
				 SET accepted_at = now()
				 WHERE token_hash = :tokenHash AND accepted_at IS NULL",
				{ tokenHash = tokenService.hashToken( arguments.token ) }
			);
		}
		return {
			success = true,
			workspaceId = invitation.workspaceId,
			workspaceName = invitation.workspaceName,
			role = invitation.role
		};
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
