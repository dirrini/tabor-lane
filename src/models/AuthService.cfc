component singleton {

	property name="passwordService" inject="PasswordService";

	struct function register(
		required string displayName,
		required string email,
		required string password,
		required string workspaceName,
		string locale = "en_US"
	){
		var normalizedEmail = lCase( trim( arguments.email ) );
		if ( emailExists( normalizedEmail ) ) {
			return { success = false, code = "email_exists" };
		}

		var userId = lCase( createUUID() );
		var workspaceId = lCase( createUUID() );
		var boardId = lCase( createUUID() );
		var slugBase = reReplace( lCase( trim( arguments.workspaceName ) ), "[^a-z0-9]+", "-", "all" );
		slugBase = reReplace( slugBase, "^-|-$", "", "all" );
		if ( !slugBase.len() ) {
			slugBase = "workspace";
		}
		var workspaceSlug = left( slugBase, 80 ) & "-" & left( replace( workspaceId, "-", "", "all" ), 8 );
		var columnIds = [ lCase( createUUID() ), lCase( createUUID() ), lCase( createUUID() ), lCase( createUUID() ) ];
		var columnNames = arguments.locale == "pt_BR"
			? [ "Ideias", "A fazer", "Em andamento", "Concluído" ]
			: [ "Ideas", "To do", "In progress", "Done" ];

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
			queryExecute(
				"INSERT INTO workspace (id, name, slug, plan)
				 VALUES (CAST(:id AS UUID), :name, :slug, 'free')",
				{ id = workspaceId, name = trim( arguments.workspaceName ), slug = workspaceSlug }
			);
			queryExecute(
				"INSERT INTO workspace_member (workspace_id, user_id, role)
				 VALUES (CAST(:workspaceId AS UUID), CAST(:userId AS UUID), 'owner')",
				{ workspaceId = workspaceId, userId = userId }
			);
			queryExecute(
				"INSERT INTO board (id, workspace_id, name, description)
				 VALUES (CAST(:id AS UUID), CAST(:workspaceId AS UUID), :name, :description)",
				{
					id = boardId,
					workspaceId = workspaceId,
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
					workspaceId = workspaceId,
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

		return {
			success = true,
			user = {
				id = userId,
				email = normalizedEmail,
				displayName = trim( arguments.displayName ),
				workspaceId = workspaceId,
				workspaceName = trim( arguments.workspaceName ),
				role = "owner",
				locale = arguments.locale
			}
		};
	}

	struct function authenticate( required string email, required string password ){
		var users = queryExecute(
			"SELECT CAST(u.id AS TEXT) AS id, u.email, u.display_name, u.password_hash, u.locale,
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

		return {
			success = true,
			user = {
				id = users[ 1 ].id,
				email = users[ 1 ].email,
				displayName = users[ 1 ].display_name,
				workspaceId = users[ 1 ].workspace_id,
				workspaceName = users[ 1 ].workspace_name,
				role = users[ 1 ].role,
				locale = users[ 1 ].locale
			}
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
