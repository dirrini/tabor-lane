component singleton {

	property name="avatarService" inject="AvatarService";
	property name="eventPublisherService" inject="EventPublisherService";

	struct function getWorkspaceBoard( required string userId, required string workspaceId, string boardId = "" ){
		var boards = queryExecute(
			"SELECT CAST(b.id AS TEXT) AS id, b.name, b.description, w.name AS workspace_name, w.plan, wm.role
			 FROM board b
			 JOIN workspace w ON w.id = b.workspace_id
			 JOIN workspace_member wm ON wm.workspace_id = w.id
			 WHERE wm.user_id = CAST(:userId AS UUID)
			   AND w.id = CAST(:workspaceId AS UUID)
			   AND b.is_archived = false
			 ORDER BY b.position,b.created_at,b.name",
			{ userId = arguments.userId, workspaceId = arguments.workspaceId },
			{ returntype = "array" }
		);
		if ( !boards.len() ) {
			return { found = false };
		}

		var requestedBoardId=urlDecode(arguments.boardId);
		var selectedBoard=boards[1];
		for(var candidate in boards){
			if(candidate.id==requestedBoardId){selectedBoard=candidate;break;}
		}
		var canViewHiddenLanes = listFindNoCase( "owner,admin", selectedBoard.role ) > 0;
		// Capture the revision before the representation. A concurrent commit can
		// therefore cause one harmless refresh, but cannot stamp stale HTML with a
		// newer revision that would remain cached indefinitely.
		var revisionResult = getBoardRevision(
			arguments.userId,
			arguments.workspaceId,
			selectedBoard.id
		);

		var columns = queryExecute(
			"SELECT CAST(bc.id AS TEXT) AS id, bc.name, bc.position, bc.wip_limit, bc.color,
			        bc.is_hidden_from_members,bc.is_completion_lane,
			        COALESCE(preference.width_px, 280) AS width_px,
			        COALESCE(preference.is_collapsed, false) AS is_collapsed
			 FROM board_column bc
			 LEFT JOIN board_column_preference preference
			   ON preference.column_id = bc.id
			  AND preference.user_id = CAST(:userId AS UUID)
			 WHERE bc.board_id = CAST(:boardId AS UUID) AND bc.is_archived=false
			   AND (bc.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
			 ORDER BY bc.position",
			{
				boardId = selectedBoard.id,
				userId = arguments.userId,
				canViewHidden = canViewHiddenLanes
			},
			{ returntype = "array" }
		);
		var cards = queryExecute(
			"SELECT CAST(c.id AS TEXT) AS id, CAST(c.column_id AS TEXT) AS column_id,
			        c.title, c.description, c.priority, array_to_string(c.labels, ',') AS labels_csv, c.due_at, c.position,
			        c.version, c.created_at,c.updated_at,c.completed_at,
			        c.completed_at IS NOT NULL AS is_completed,
			        c.blocked_at IS NOT NULL AS is_blocked,
			        COALESCE(att.attachment_count, 0) AS attachment_count,
			        COALESCE(att.attachment_names, '') AS attachment_names
			 FROM card c
			 JOIN board_column card_column
			   ON card_column.id=c.column_id
			  AND card_column.board_id=c.board_id
			  AND card_column.is_archived=false
			 LEFT JOIN LATERAL (
			     SELECT COUNT(*) AS attachment_count,
			            string_agg(a.original_filename, CHR(10) ORDER BY a.created_at) AS attachment_names
			     FROM attachment a
			     WHERE a.card_id = c.id AND a.status = 'available' AND a.deleted_at IS NULL
			 ) att ON true
			 WHERE c.board_id = CAST(:boardId AS UUID) AND c.archived_at IS NULL
			   AND (card_column.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
			 ORDER BY c.column_id, c.position, c.created_at",
			{ boardId = selectedBoard.id, canViewHidden = canViewHiddenLanes },
			{ returntype = "array" }
		);
		var cardsById = {};
		for ( var boardCard in cards ) {
			boardCard.assignees = [];
			cardsById[ boardCard.id ] = boardCard;
		}
		var assignmentRows = queryExecute(
			"SELECT CAST(assignment.card_id AS TEXT) AS card_id,
			        CAST(account.id AS TEXT) AS user_id,account.display_name,
			        CAST(avatar.id AS TEXT) AS avatar_id
			 FROM card_assignee assignment
			 JOIN card card_record
			   ON card_record.id=assignment.card_id
			  AND card_record.workspace_id=assignment.workspace_id
			 JOIN board_column assignment_lane
			   ON assignment_lane.id=card_record.column_id
			  AND assignment_lane.board_id=card_record.board_id
			  AND assignment_lane.is_archived=false
			 JOIN workspace_member membership
			   ON membership.workspace_id=assignment.workspace_id
			  AND membership.user_id=assignment.user_id
			 JOIN app_user account ON account.id=assignment.user_id
			 LEFT JOIN user_avatar avatar
			   ON avatar.user_id=account.id
			  AND avatar.status='available' AND avatar.deleted_at IS NULL
			 WHERE card_record.board_id=CAST(:boardId AS UUID)
			   AND card_record.archived_at IS NULL
			   AND (assignment_lane.is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
			 ORDER BY assignment.created_at,account.display_name,account.id",
			{ boardId=selectedBoard.id,canViewHidden=canViewHiddenLanes },
			{ returntype="array" }
		);
		for ( var assignmentRow in assignmentRows ) {
			assignmentRow.initials = avatarService.initials( assignmentRow.display_name );
			if ( structKeyExists( cardsById, assignmentRow.card_id ) ) {
				cardsById[ assignmentRow.card_id ].assignees.append( assignmentRow );
			}
		}

		var progressColumnIds = [];
		for ( var progressColumn in columns ) {
			if ( !( progressColumn.is_hidden_from_members ?: false ) ) {
				progressColumnIds.append( progressColumn.id );
			}
		}
		var totalCards = 0;
		var completedCards = 0;
		for ( var progressCard in cards ) {
			if ( arrayFindNoCase( progressColumnIds, progressCard.column_id ) ) {
				totalCards++;
				if ( progressCard.is_completed ?: false ) completedCards++;
			}
		}
		for ( var column in columns ) {
			column.cards = [];
			column.completion_state = ( column.is_completion_lane ?: false )
				? "complete"
				: ( ( column.is_hidden_from_members ?: false ) ? "preserve" : "active" );
			for ( var card in cards ) {
				if ( card.column_id == column.id ) {
					column.cards.append( card );
				}
			}
		}

		return {
			found=true,
			board=selectedBoard,
			boards=boards,
			columns=columns,
			revision=revisionResult.found ? revisionResult.revision : "",
			totalCards=totalCards,
			completedCards=completedCards,
			progressPercent=totalCards ? round( completedCards * 100 / totalCards ) : 0
		};
	}

	struct function getBoardRevision(
		required string userId,
		required string workspaceId,
		required string boardId
	){
		if (
			!isCanonicalUuid( arguments.userId )
			|| !isCanonicalUuid( arguments.workspaceId )
			|| !isCanonicalUuid( arguments.boardId )
		) return { found=false };

		var rows = queryExecute(
			"SELECT md5(concat_ws('|',
			        CAST(board_record.updated_at AS TEXT),requester.role,
			        COALESCE((
			            SELECT md5(COALESCE(string_agg(
			                CAST(jsonb_build_array(
				                    lane.id,lane.name,lane.position,lane.wip_limit,lane.color,
				                    lane.is_hidden_from_members,lane.is_completion_lane,lane.updated_at
			                ) AS TEXT),'|' ORDER BY lane.id),''))
			            FROM board_column lane
			            WHERE lane.board_id=board_record.id
			              AND lane.is_archived=false
			              AND (lane.is_hidden_from_members=false OR requester.role IN ('owner','admin'))
			        ),md5('')),
			        COALESCE((
			            SELECT md5(COALESCE(string_agg(
			                CAST(jsonb_build_array(
			                    card_record.id,card_record.column_id,card_record.title,
			                    card_record.position,card_record.version,card_record.updated_at,
			                    card_record.completed_at,card_record.blocked_at
			                ) AS TEXT),'|' ORDER BY card_record.id),''))
			            FROM card card_record
			            JOIN board_column card_lane
			              ON card_lane.id=card_record.column_id
			             AND card_lane.board_id=card_record.board_id
			             AND card_lane.is_archived=false
			            WHERE card_record.board_id=board_record.id
			              AND card_record.archived_at IS NULL
			              AND (card_lane.is_hidden_from_members=false OR requester.role IN ('owner','admin'))
			        ),md5('')),
			        COALESCE((
			            SELECT md5(COALESCE(string_agg(
			                CAST(jsonb_build_array(
			                    assignment.card_id,assignment.user_id,account.display_name,
			                    account.updated_at,active_avatar.id,active_avatar.updated_at
			                ) AS TEXT),'|' ORDER BY assignment.card_id,assignment.user_id),''))
			            FROM card_assignee assignment
			            JOIN card assigned_card
			              ON assigned_card.id=assignment.card_id
			             AND assigned_card.workspace_id=assignment.workspace_id
			             AND assigned_card.archived_at IS NULL
			            JOIN board_column assigned_lane
			              ON assigned_lane.id=assigned_card.column_id
			             AND assigned_lane.board_id=assigned_card.board_id
			             AND assigned_lane.is_archived=false
			            JOIN app_user account ON account.id=assignment.user_id
			            LEFT JOIN user_avatar active_avatar
			              ON active_avatar.user_id=assignment.user_id
			             AND active_avatar.status='available' AND active_avatar.deleted_at IS NULL
			            WHERE assigned_card.board_id=board_record.id
			              AND (assigned_lane.is_hidden_from_members=false OR requester.role IN ('owner','admin'))
			        ),md5(''))
			    )) AS revision
			 FROM board board_record
			 JOIN workspace_member requester
			   ON requester.workspace_id=board_record.workspace_id
			  AND requester.user_id=CAST(:userId AS UUID)
			 WHERE board_record.id=CAST(:boardId AS UUID)
			   AND board_record.workspace_id=CAST(:workspaceId AS UUID)
			   AND board_record.is_archived=false",
			{
				userId=arguments.userId,
				workspaceId=arguments.workspaceId,
				boardId=arguments.boardId
			},
			{ returntype="array" }
		);
		return rows.len()
			? { found=true,revision=rows[ 1 ].revision }
			: { found=false };
	}

	struct function createCard(
		required string userId,
		required string workspaceId,
		required string columnId,
		required string title,
		string description = ""
	){
		var normalizedTitle = trim( arguments.title );
		if ( !isCanonicalUuid( arguments.columnId ) ) {
			return { success=false,code="forbidden" };
		}
		var cardId = canonicalUuid( createUUID() );
		var outcome = { success=false,code="forbidden" };
		transaction {
			// Lock order is the shared collaboration mutex: board first, then lane.
			// This serializes WIP checks with lane archive/reorder operations.
			var boardAccess = queryExecute(
				"SELECT CAST(board_record.id AS TEXT) AS board_id,membership.role
				 FROM board board_record
				 JOIN board_column requested_lane ON requested_lane.board_id=board_record.id
				 JOIN workspace_member membership
				   ON membership.workspace_id=board_record.workspace_id
				  AND membership.user_id=CAST(:userId AS UUID)
				 WHERE requested_lane.id=CAST(:columnId AS UUID)
				   AND board_record.is_archived=false
				   AND board_record.workspace_id=CAST(:workspaceId AS UUID)
				 FOR UPDATE OF board_record
				 FOR SHARE OF membership",
				{
					columnId=arguments.columnId,
					workspaceId=arguments.workspaceId,
					userId=arguments.userId
				},
				{ returntype="array" }
			);
			var access = [];
			if ( boardAccess.len() ) {
				access = queryExecute(
					"SELECT name AS lane_name,wip_limit,is_completion_lane
					 FROM board_column
					 WHERE id=CAST(:columnId AS UUID)
					   AND board_id=CAST(:boardId AS UUID)
					   AND is_archived=false
					   AND (is_hidden_from_members=false OR CAST(:canViewHidden AS BOOLEAN))
					 FOR UPDATE",
					{
						columnId=arguments.columnId,
						boardId=boardAccess[ 1 ].board_id,
						canViewHidden=listFindNoCase( "owner,admin", boardAccess[ 1 ].role ) > 0
					},
					{ returntype="array" }
				);
				if ( access.len() ) {
					access[ 1 ][ "board_id" ] = boardAccess[ 1 ].board_id;
					access[ 1 ][ "role" ] = boardAccess[ 1 ].role;
				}
			}
			if ( !access.len() ) {
				outcome = { success=false,code="forbidden" };
			} else if ( access[ 1 ].role == "viewer" ) {
				outcome = { success=false,code="read_only",boardId=access[ 1 ].board_id };
			} else if ( !normalizedTitle.len() || normalizedTitle.len() > 255 ) {
				outcome = { success=false,code="invalid",boardId=access[ 1 ].board_id };
			} else {
				var targetCount = queryExecute(
					"SELECT COUNT(*) AS total FROM card
					 WHERE column_id=CAST(:columnId AS UUID)
					   AND archived_at IS NULL",
					{ columnId=arguments.columnId },
					{ returntype="array" }
				)[ 1 ].total;
				var hasWipLimit = !isNull( access[ 1 ].wip_limit )
					&& toString( access[ 1 ].wip_limit ).len()
					&& val( access[ 1 ].wip_limit ) > 0;
				if ( hasWipLimit && targetCount >= val( access[ 1 ].wip_limit ) ) {
					outcome = { success=false,code="wip_limit",boardId=access[ 1 ].board_id };
				} else {
					var createdRows = queryExecute(
				"WITH visible_lifecycle AS (
				     SELECT MIN(position) AS first_position
				     FROM board_column
				     WHERE board_id=CAST(:boardId AS UUID)
				       AND is_archived=false
				       AND is_hidden_from_members=false
				 )
				 INSERT INTO card (
				     id,workspace_id,board_id,column_id,title,description,position,started_at,completed_at
				 )
				 SELECT CAST(:cardId AS UUID),CAST(:workspaceId AS UUID),CAST(:boardId AS UUID),
				        CAST(:columnId AS UUID),:title,:description,
				        (
				            SELECT COALESCE(MAX(existing.position),0)+1
				            FROM card existing
				            WHERE existing.column_id=CAST(:columnId AS UUID)
				              AND existing.archived_at IS NULL
				        ),
				        CASE
				            WHEN target.is_hidden_from_members=false
				             AND target.position=visible_lifecycle.first_position
				            THEN NULL
				            ELSE now()
				        END,
					        CASE WHEN target.is_completion_lane THEN now() ELSE NULL END
				 FROM board_column target
				 CROSS JOIN visible_lifecycle
				 WHERE target.id=CAST(:columnId AS UUID)
				   AND target.board_id=CAST(:boardId AS UUID)
				   AND target.is_archived=false
				 RETURNING CAST(id AS TEXT) AS id",
				{
					cardId = cardId,
					workspaceId = arguments.workspaceId,
					boardId = access[ 1 ].board_id,
					columnId = arguments.columnId,
					title = normalizedTitle,
					description = trim( arguments.description )
				},
				{ returntype="array" }
					);
					if ( createdRows.len() ) {
						recordActivity( cardId, arguments.userId, "created" );
						var createdPayload = {};
						createdPayload[ "cardTitle" ] = normalizedTitle;
						createdPayload[ "boardId" ] = access[ 1 ].board_id;
						createdPayload[ "laneId" ] = arguments.columnId;
						createdPayload[ "laneName" ] = access[ 1 ].lane_name;
						eventPublisherService.publish(
							workspaceId = arguments.workspaceId,
							eventType = "card.created",
							aggregateType = "card",
							aggregateId = cardId,
							actorId = arguments.userId,
							recipientUserIds = [],
							payload = createdPayload,
							deduplicationKey = "card.created:#cardId#"
						);
						if ( access[ 1 ].is_completion_lane ?: false ) {
							var completedPayload = {};
							completedPayload[ "cardTitle" ] = normalizedTitle;
							completedPayload[ "boardId" ] = access[ 1 ].board_id;
							completedPayload[ "laneId" ] = arguments.columnId;
							completedPayload[ "laneName" ] = access[ 1 ].lane_name;
							eventPublisherService.publish(
								workspaceId = arguments.workspaceId,
								eventType = "card.completed",
								aggregateType = "card",
								aggregateId = cardId,
								actorId = arguments.userId,
								recipientUserIds = [],
								payload = completedPayload,
								deduplicationKey = "card.completed:#cardId#:1"
							);
						}
						outcome = {
							success=true,
							cardId=cardId,
							boardId=access[ 1 ].board_id
						};
					} else {
						outcome = { success=false,code="forbidden",boardId=access[ 1 ].board_id };
					}
				}
			}
		}
		return outcome;
	}

	struct function moveCard(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string columnId,
		string beforeCardId = ""
	){
		var outcome = { success = false, code = "forbidden" };
		transaction {
			outcome = moveCardLocked(
				userId = arguments.userId,
				workspaceId = arguments.workspaceId,
				cardId = arguments.cardId,
				columnId = arguments.columnId,
				beforeCardId = arguments.beforeCardId
			);
		}
		return outcome;
	}

	private struct function moveCardLocked(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string columnId,
		string beforeCardId = ""
	){
		var cardHints = queryExecute(
			"SELECT CAST(board_id AS TEXT) AS board_id
			 FROM card
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardHints.len() ) {
			return { success = false, code = "forbidden" };
		}

		// Lock order: board mutex -> card/lanes -> ordered lane cards.
		// The board mutex serializes WIP checks and reorder writes.
		var boardLocks = queryExecute(
			"SELECT id
			 FROM board
			 WHERE id=CAST(:boardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			   AND is_archived=false
			 FOR UPDATE",
			{
				boardId = cardHints[ 1 ].board_id,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !boardLocks.len() ) {
			return { success = false, code = "forbidden" };
		}

		var rows = queryExecute(
			"SELECT CAST(c.column_id AS TEXT) AS from_column_id,source.name AS from_column_name,
			        CAST(c.board_id AS TEXT) AS board_id,c.title AS card_title,c.version,
			        c.completed_at IS NOT NULL AS was_completed,
			        wm.role,target.wip_limit,target.name AS to_column_name,
			        target.is_completion_lane AS target_completes_cards,
			        target.is_hidden_from_members AS target_is_hidden
			 FROM card c
			 JOIN board b
			   ON b.id=c.board_id
			  AND b.workspace_id=c.workspace_id
			  AND b.is_archived=false
			 JOIN workspace_member wm ON wm.workspace_id = c.workspace_id
			 JOIN board_column source
			   ON source.id=c.column_id
			  AND source.board_id=c.board_id
			  AND source.is_archived=false
			 JOIN board_column target ON target.id = CAST(:columnId AS UUID) AND target.board_id = c.board_id AND target.is_archived=false
			 WHERE c.id = CAST(:cardId AS UUID)
			   AND c.workspace_id = CAST(:workspaceId AS UUID)
			   AND c.board_id = CAST(:boardId AS UUID)
			   AND wm.user_id = CAST(:userId AS UUID)
			   AND c.archived_at IS NULL
			   AND (source.is_hidden_from_members=false OR wm.role IN ('owner','admin'))
			   AND (target.is_hidden_from_members=false OR wm.role IN ('owner','admin'))
			 FOR UPDATE OF c,source,target
			 FOR SHARE OF wm",
			{
				columnId = arguments.columnId,
				cardId = arguments.cardId,
				boardId = cardHints[ 1 ].board_id,
				workspaceId = arguments.workspaceId,
				userId = arguments.userId
			},
			{ returntype = "array" }
		);
		if ( !rows.len() ) {
			return { success = false, code = "forbidden" };
		}
		if ( rows[ 1 ].role == "viewer" ) {
			return { success = false, code = "read_only" };
		}
		var cleanBeforeCardId = trim( arguments.beforeCardId );
		if ( cleanBeforeCardId.len() ) {
			var validBeforeCard = queryExecute(
				"SELECT 1
				 FROM card
				 WHERE id = CAST(:beforeCardId AS UUID)
				   AND id <> CAST(:cardId AS UUID)
				   AND board_id = CAST(:boardId AS UUID)
				   AND column_id = CAST(:columnId AS UUID)
				   AND archived_at IS NULL
				 FOR UPDATE",
				{
					beforeCardId = cleanBeforeCardId,
					cardId = arguments.cardId,
					boardId = rows[ 1 ].board_id,
					columnId = arguments.columnId
				},
				{ returntype = "array" }
			);
			if ( !validBeforeCard.len() ) {
				return { success = false, code = "invalid_position" };
			}
		}
		var targetWip=rows[1].wip_limit ?: "";
		if(toString(targetWip).len() && rows[1].from_column_id!=arguments.columnId){
			var targetCount=queryExecute(
				"SELECT COUNT(*) total FROM card WHERE column_id=CAST(:column AS UUID) AND archived_at IS NULL",
				{column=arguments.columnId},{returntype="array"}
			)[1].total;
			if(targetCount>=val(targetWip)) return {success=false,code="wip_limit"};
		}

		var columnChanged = rows[ 1 ].from_column_id != arguments.columnId;
		var moveEventType = columnChanged ? "card.moved" : "card.reordered";
		var completesAfterMove = rows[ 1 ].target_completes_cards
			|| ( rows[ 1 ].target_is_hidden && rows[ 1 ].was_completed );
		var moveAssigneeIds = getCardAssigneeIds( arguments.workspaceId, arguments.cardId );
		var moveRecipients = recipientsExcept( moveAssigneeIds, arguments.userId );
		var eventVersion = val( rows[ 1 ].version ) + 1;
		queryExecute(
			"SELECT id
				 FROM card
				 WHERE board_id = CAST(:boardId AS UUID)
				   AND column_id IN (CAST(:fromColumnId AS UUID), CAST(:columnId AS UUID))
				   AND archived_at IS NULL
				 ORDER BY column_id,position,created_at,id
				 FOR UPDATE",
				{
					boardId = rows[ 1 ].board_id,
					fromColumnId = rows[ 1 ].from_column_id,
					columnId = arguments.columnId
				}
		);

			var versionRows = [];
			if ( columnChanged ) {
				versionRows = queryExecute(
					"UPDATE card
					 SET column_id = CAST(:columnId AS UUID),
					     started_at = COALESCE(started_at, now()),
					     completed_at = CASE
					         WHEN CAST(:targetCompletes AS BOOLEAN)
					         THEN COALESCE(completed_at,now())
					         WHEN CAST(:targetIsHidden AS BOOLEAN)
					         THEN completed_at
					         ELSE NULL END,
					     version = version + 1,
					     updated_at = now()
					 WHERE id = CAST(:cardId AS UUID)
					 RETURNING version",
					{
						columnId = arguments.columnId,
						targetCompletes = rows[ 1 ].target_completes_cards,
						targetIsHidden = rows[ 1 ].target_is_hidden,
						cardId = arguments.cardId
					},
					{ returntype = "array" }
				);
				if ( versionRows.len() ) eventVersion = val( versionRows[ 1 ].version );
				queryExecute(
					"INSERT INTO card_transition (workspace_id, card_id, from_column_id, to_column_id, actor_user_id)
					 VALUES (CAST(:workspaceId AS UUID), CAST(:cardId AS UUID), CAST(:fromColumnId AS UUID),
					         CAST(:columnId AS UUID), CAST(:userId AS UUID))",
					{
						workspaceId = arguments.workspaceId,
						cardId = arguments.cardId,
						fromColumnId = rows[ 1 ].from_column_id,
						columnId = arguments.columnId,
						userId = arguments.userId
					}
				);
			} else {
				versionRows = queryExecute(
					"UPDATE card
					 SET version=version+1,updated_at=now()
					 WHERE id=CAST(:cardId AS UUID)
					 RETURNING version",
					{ cardId=arguments.cardId },
					{ returntype="array" }
				);
				if ( versionRows.len() ) eventVersion = val( versionRows[ 1 ].version );
			}

			var targetCards = queryExecute(
				"SELECT CAST(id AS TEXT) AS id
				 FROM card
				 WHERE column_id=CAST(:columnId AS UUID)
				   AND archived_at IS NULL
				   AND id<>CAST(:cardId AS UUID)
				 ORDER BY position,created_at,id",
				{ columnId=arguments.columnId, cardId=arguments.cardId },
				{ returntype="array" }
			);
			var targetCardIds = [];
			for ( var targetCard in targetCards ) {
				targetCardIds.append( targetCard.id );
			}
			var inserted = false;
			if ( cleanBeforeCardId.len() ) {
				for ( var targetIndex=1; targetIndex<=targetCardIds.len(); targetIndex++ ) {
					if ( targetCardIds[ targetIndex ] == cleanBeforeCardId ) {
						targetCardIds.insertAt( targetIndex, arguments.cardId );
						inserted = true;
						break;
					}
				}
			}
			if ( !inserted ) {
				targetCardIds.append( arguments.cardId );
			}
			for ( var positionIndex=1; positionIndex<=targetCardIds.len(); positionIndex++ ) {
				queryExecute(
					"UPDATE card SET position=CAST(:position AS NUMERIC) WHERE id=CAST(:cardId AS UUID)",
					{ position=positionIndex, cardId=targetCardIds[ positionIndex ] }
				);
			}

			if ( columnChanged ) {
				var sourceCards = queryExecute(
					"SELECT CAST(id AS TEXT) AS id
					 FROM card
					 WHERE column_id=CAST(:columnId AS UUID) AND archived_at IS NULL
					 ORDER BY position,created_at,id",
					{ columnId=rows[ 1 ].from_column_id },
					{ returntype="array" }
				);
				for ( var sourceIndex=1; sourceIndex<=sourceCards.len(); sourceIndex++ ) {
					queryExecute(
						"UPDATE card SET position=CAST(:position AS NUMERIC) WHERE id=CAST(:cardId AS UUID)",
						{ position=sourceIndex, cardId=sourceCards[ sourceIndex ].id }
					);
				}
			}

			recordActivity(
				arguments.cardId,
				arguments.userId,
				columnChanged ? "moved" : "reordered"
			);
			var movePayload = {};
			movePayload[ "cardTitle" ] = rows[ 1 ].card_title;
			movePayload[ "boardId" ] = rows[ 1 ].board_id;
			movePayload[ "fromLaneId" ] = rows[ 1 ].from_column_id;
			movePayload[ "fromLaneName" ] = rows[ 1 ].from_column_name;
			movePayload[ "toLaneId" ] = arguments.columnId;
			movePayload[ "toLaneName" ] = rows[ 1 ].to_column_name;
			movePayload[ "assigneeIds" ] = moveAssigneeIds;
			movePayload[ "assigneeId" ] = moveAssigneeIds.len() ? moveAssigneeIds[ 1 ] : "";
			movePayload[ "beforeCardId" ] = cleanBeforeCardId;
		eventPublisherService.publish(
				workspaceId = arguments.workspaceId,
				eventType = moveEventType,
				aggregateType = "card",
				aggregateId = arguments.cardId,
				actorId = arguments.userId,
				recipientUserIds = moveRecipients,
				payload = movePayload,
				deduplicationKey = "#moveEventType#:#arguments.cardId#:#eventVersion#"
		);
		if ( columnChanged && completesAfterMove != rows[ 1 ].was_completed ) {
			var completionEventType = completesAfterMove ? "card.completed" : "card.reopened";
			var completionPayload = {};
			completionPayload[ "cardTitle" ] = rows[ 1 ].card_title;
			completionPayload[ "boardId" ] = rows[ 1 ].board_id;
			completionPayload[ "laneId" ] = arguments.columnId;
			completionPayload[ "laneName" ] = rows[ 1 ].to_column_name;
			eventPublisherService.publish(
				workspaceId = arguments.workspaceId,
				eventType = completionEventType,
				aggregateType = "card",
				aggregateId = arguments.cardId,
				actorId = arguments.userId,
				recipientUserIds = [],
				payload = completionPayload,
				deduplicationKey = "#completionEventType#:#arguments.cardId#:#eventVersion#"
			);
		}
		var revisionResult = getBoardRevision(
			arguments.userId,
			arguments.workspaceId,
			rows[ 1 ].board_id
		);
		return {
			success=true,
			revision=revisionResult.found ? revisionResult.revision : ""
		};
	}

	struct function saveLanePreference(
		required string userId,
		required string workspaceId,
		required string columnId,
		required numeric widthPx,
		required boolean isCollapsed
	){
		var access = queryExecute(
			"SELECT 1
			 FROM board_column bc
			 JOIN board b ON b.id=bc.board_id AND b.is_archived=false
			 JOIN workspace_member wm ON wm.workspace_id=b.workspace_id
			 WHERE bc.id=CAST(:columnId AS UUID)
			   AND bc.is_archived=false
			   AND b.workspace_id=CAST(:workspaceId AS UUID)
			   AND wm.user_id=CAST(:userId AS UUID)
			   AND (bc.is_hidden_from_members=false OR wm.role IN ('owner','admin'))",
			{ columnId=arguments.columnId, workspaceId=arguments.workspaceId, userId=arguments.userId },
			{ returntype="array" }
		);
		if ( !access.len() ) return { success=false, code="forbidden" };

		var safeWidth = max( 240, min( 1200, round( arguments.widthPx ) ) );
		queryExecute(
			"INSERT INTO board_column_preference(user_id,column_id,width_px,is_collapsed)
			 VALUES(CAST(:userId AS UUID),CAST(:columnId AS UUID),CAST(:widthPx AS INTEGER),CAST(:isCollapsed AS BOOLEAN))
			 ON CONFLICT(user_id,column_id) DO UPDATE
			 SET width_px=EXCLUDED.width_px,is_collapsed=EXCLUDED.is_collapsed,updated_at=now()",
			{
				userId=arguments.userId,
				columnId=arguments.columnId,
				widthPx=safeWidth,
				isCollapsed=arguments.isCollapsed
			}
		);
		return { success=true, widthPx=safeWidth, isCollapsed=arguments.isCollapsed };
	}

	struct function getCardDetails( required string userId, required string workspaceId, required string cardId ){
		var cards = queryExecute(
			"SELECT CAST(c.id AS TEXT) id, c.title, c.description, c.priority, array_to_string(c.labels, ',') AS labels_csv,
			        to_char(c.due_at AT TIME ZONE 'UTC','YYYY-MM-DD') due_date,
			        c.created_at,c.updated_at,c.completed_at,c.blocked_at,
			        c.completed_at IS NOT NULL AS is_completed,
			        c.blocked_at IS NOT NULL AS is_blocked,c.version,
			        CAST(b.id AS TEXT) board_id,b.name board_name, bc.name column_name, access.role AS access_role
			 FROM card c JOIN board b ON b.id=c.board_id JOIN board_column bc ON bc.id=c.column_id
			 JOIN workspace_member access ON access.workspace_id=c.workspace_id
			 WHERE c.id=CAST(:cardId AS UUID) AND c.workspace_id=CAST(:workspaceId AS UUID)
			   AND access.user_id=CAST(:userId AS UUID) AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))",
			{ cardId=arguments.cardId, workspaceId=arguments.workspaceId, userId=arguments.userId },
			{ returntype="array" }
		);
		if ( !cards.len() ) return { found=false };
		var members = queryExecute(
			"SELECT CAST(u.id AS TEXT) id,u.display_name,
			        CAST(member_avatar.id AS TEXT) AS avatar_id,
			        EXISTS(
			            SELECT 1 FROM card_assignee assignment
			            WHERE assignment.workspace_id=wm.workspace_id
			              AND assignment.card_id=CAST(:cardId AS UUID)
			              AND assignment.user_id=wm.user_id
			        ) AS is_assigned
			 FROM workspace_member wm
			 JOIN app_user u ON u.id=wm.user_id
			 LEFT JOIN user_avatar member_avatar
			   ON member_avatar.user_id=u.id
			  AND member_avatar.status='available' AND member_avatar.deleted_at IS NULL
			 WHERE wm.workspace_id=CAST(:workspaceId AS UUID)
			 ORDER BY u.display_name",
			{ workspaceId=arguments.workspaceId,cardId=arguments.cardId },
			{ returntype="array" }
		);
		var selectedAssigneeIds = [];
		for ( var member in members ) {
			member.initials = avatarService.initials( member.display_name );
			if ( member.is_assigned ) selectedAssigneeIds.append( member.id );
		}
		cards[ 1 ].assignee_ids = selectedAssigneeIds;
		var comments = queryExecute(
			"SELECT cc.body,cc.created_at,CAST(u.id AS TEXT) AS author_id,
			        COALESCE(u.display_name,'Former member') author_name,
			        CAST(author_avatar.id AS TEXT) AS author_avatar_id
			 FROM card_comment cc
			 LEFT JOIN app_user u ON u.id=cc.author_id
			 LEFT JOIN workspace_member author_membership
			   ON author_membership.user_id=u.id
			  AND author_membership.workspace_id=CAST(:workspaceId AS UUID)
			 LEFT JOIN user_avatar author_avatar
			   ON author_avatar.user_id=u.id
			  AND author_avatar.status='available' AND author_avatar.deleted_at IS NULL
			  AND author_membership.user_id IS NOT NULL
			 WHERE cc.card_id=CAST(:cardId AS UUID)
			 ORDER BY cc.created_at",
			{ cardId=arguments.cardId, workspaceId=arguments.workspaceId },
			{ returntype="array" }
		);
		for ( var comment in comments ) {
			comment.author_initials = avatarService.initials( comment.author_name );
		}
		return {
			found=true,
			card=cards[1],
			members=members,
			comments=comments,
			activity=queryExecute(
				"SELECT ca.action,ca.created_at,COALESCE(u.display_name,'System') actor_name FROM card_activity ca LEFT JOIN app_user u ON u.id=ca.actor_id WHERE ca.card_id=CAST(:cardId AS UUID) ORDER BY ca.created_at DESC LIMIT 50",
				{ cardId=arguments.cardId }, { returntype="array" }
			)
		};
	}

	struct function updateCard( required string userId, required string workspaceId, required string cardId, required struct data ){
		var outcome = { success = false };
		transaction {
			outcome = updateCardLocked(
				userId = arguments.userId,
				workspaceId = arguments.workspaceId,
				cardId = arguments.cardId,
				data = arguments.data
			);
		}
		return outcome;
	}

	struct function patchCard(
		required string userId,
		required string workspaceId,
		required string cardId,
		required struct data
	){
		var outcome = { success=false,code="forbidden" };
		transaction {
			var currentRows = queryExecute(
				"SELECT c.title,COALESCE(c.description,'') AS description,
				        c.priority,array_to_string(c.labels, ',') AS labels,
				        COALESCE(to_char(c.due_at AT TIME ZONE 'UTC','YYYY-MM-DD'),'') AS due_date,
				        c.blocked_at IS NOT NULL AS is_blocked,c.version,
				        access.role AS access_role
				 FROM card c
				 JOIN board b
				   ON b.id=c.board_id
				  AND b.workspace_id=c.workspace_id
				  AND b.is_archived=false
				 JOIN board_column bc
				   ON bc.id=c.column_id
				  AND bc.board_id=c.board_id
				  AND bc.is_archived=false
				 JOIN workspace_member access
				   ON access.workspace_id=c.workspace_id
				  AND access.user_id=CAST(:userId AS UUID)
				 WHERE c.id=CAST(:cardId AS UUID)
				   AND c.workspace_id=CAST(:workspaceId AS UUID)
				   AND c.archived_at IS NULL
				   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))
				 FOR UPDATE OF c
				 FOR SHARE OF access",
				{
					userId=arguments.userId,
					workspaceId=arguments.workspaceId,
					cardId=arguments.cardId
				},
				{ returntype="array" }
			);
			if ( currentRows.len() ) {
				var current = currentRows[ 1 ];
				if ( current.access_role == "viewer" ) {
					outcome = { success=false,code="read_only" };
				} else if (
					structKeyExists( arguments.data, "expectedVersion" )
					&& val( arguments.data.expectedVersion ) != val( current.version )
				) {
					outcome = {
						success=false,
						code="version_conflict",
						version=val( current.version )
					};
				} else {
					var currentAssigneeIds = getCardAssigneeIds(
						arguments.workspaceId,
						arguments.cardId,
						false
					);
					var merged = {};
					merged[ "title" ] = structKeyExists( arguments.data, "title" )
						? arguments.data.title
						: current.title;
					merged[ "description" ] = structKeyExists( arguments.data, "description" )
						? arguments.data.description
						: current.description;
					merged[ "priority" ] = structKeyExists( arguments.data, "priority" )
						? arguments.data.priority
						: current.priority;
					merged[ "dueDate" ] = structKeyExists( arguments.data, "dueDate" )
						? arguments.data.dueDate
						: current.due_date;
					merged[ "labels" ] = structKeyExists( arguments.data, "labels" )
						? (
							isArray( arguments.data.labels )
								? arrayToList( arguments.data.labels )
								: arguments.data.labels
						)
						: ( current.labels ?: "" );
					merged[ "assigneeIds" ] = structKeyExists( arguments.data, "assigneeIds" )
						? arguments.data.assigneeIds
						: currentAssigneeIds;
					merged[ "isBlocked" ] = structKeyExists( arguments.data, "isBlocked" )
						? arguments.data.isBlocked
						: current.is_blocked;
					outcome = updateCardLocked(
						userId=arguments.userId,
						workspaceId=arguments.workspaceId,
						cardId=arguments.cardId,
						data=merged
					);
				}
			}
		}
		return outcome;
	}

	private struct function updateCardLocked(
		required string userId,
		required string workspaceId,
		required string cardId,
		required struct data
	){
		var cardLockRows = queryExecute(
			"SELECT 1
			 FROM card
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			 FOR UPDATE",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardLockRows.len() ) return { success = false };

		var cardRows = queryExecute(
			"SELECT c.title,c.description,c.priority,c.blocked_at,
			        c.version,CAST(c.board_id AS TEXT) AS board_id,
			        access.role AS access_role
			 FROM card c
			 JOIN board b
			   ON b.id=c.board_id
			  AND b.workspace_id=c.workspace_id
			  AND b.is_archived=false
			 JOIN board_column bc
			   ON bc.id=c.column_id
			  AND bc.board_id=c.board_id
			  AND bc.is_archived=false
			 JOIN workspace_member access
			   ON access.workspace_id=c.workspace_id
			  AND access.user_id=CAST(:userId AS UUID)
			 WHERE c.id=CAST(:cardId AS UUID)
			   AND c.workspace_id=CAST(:workspaceId AS UUID)
			   AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))
			 FOR UPDATE OF c
			 FOR SHARE OF access",
			{
				userId = arguments.userId,
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		var access = { found = cardRows.len() > 0 };
		if ( access.found ) access[ "card" ] = cardRows[ 1 ];
		if(!access.found) return {success=false};
		if ( access.card.access_role == "viewer" ) return { success=false, code="read_only" };
		var priority=listFindNoCase("none,low,medium,high,urgent",arguments.data.priority ?: "")?lCase(arguments.data.priority):"none";
		var normalizedAssignees = normalizeAssigneeIds(
			arguments.data.assigneeIds ?: ( arguments.data.assigneeId ?: "" )
		);
		if ( !normalizedAssignees.success ) {
			return { success=false,code="invalid_assignees" };
		}
		if ( normalizedAssignees.ids.len() ) {
			var validAssignees = queryExecute(
				"SELECT CAST(membership.user_id AS TEXT) AS user_id
				 FROM workspace_member membership
				 JOIN jsonb_array_elements_text(CAST(:assigneeIds AS JSONB)) requested(user_id)
				   ON membership.user_id=CAST(requested.user_id AS UUID)
				 WHERE membership.workspace_id=CAST(:workspaceId AS UUID)
				 FOR SHARE OF membership",
				{
					workspaceId=arguments.workspaceId,
					assigneeIds=serializeJSON( normalizedAssignees.ids )
				},
				{ returntype="array" }
			);
			if ( validAssignees.len() != normalizedAssignees.ids.len() ) {
				return { success=false,code="invalid_assignees" };
			}
		}
		var previousAssigneeIds = getCardAssigneeIds(
			arguments.workspaceId,
			arguments.cardId,
			true
		);
		var labelList=listToArray(arguments.data.labels ?: "");
		var cleanLabels=[];
		for(var label in labelList){
			var cleanLabel=trim(label);
			if(cleanLabel.len() && !arrayFindNoCase(cleanLabels,cleanLabel)) cleanLabels.append(left(cleanLabel,40));
			if(cleanLabels.len() == 10) break;
		}
		var normalizedTitle = trim( arguments.data.title );
		var normalizedDueDate = trim( arguments.data.dueDate ?: "" );
		var isBlocked = isTruthy( arguments.data.isBlocked ?: "" );
		var wasBlocked = structKeyExists( access.card, "blocked_at" )
			&& !isNull( access.card.blocked_at )
			&& toString( access.card.blocked_at ).len();
		var assignmentChanged = !sameUuidSet( previousAssigneeIds, normalizedAssignees.ids );
		var eventVersion = val( access.card.version ) + 1;
		var updateRows = queryExecute(
			"UPDATE card SET title=:title,description=:description,priority=:priority,
			 due_at=CASE WHEN :dueDate='' THEN NULL ELSE CAST(:dueDate AS DATE) END,
			 labels=string_to_array(:labels,','),
			 blocked_at=CASE
			     WHEN CAST(:isBlocked AS BOOLEAN) THEN COALESCE(blocked_at,now())
			     ELSE NULL
			 END,
			 blocked_by=CASE
			     WHEN CAST(:isBlocked AS BOOLEAN) THEN COALESCE(blocked_by,CAST(:userId AS UUID))
			     ELSE NULL
			 END,
			 version=version+1,updated_at=now()
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			   AND archived_at IS NULL
			 RETURNING version",
			{
				title=normalizedTitle,
				description=trim(arguments.data.description ?: ""),
				priority=priority,
				dueDate=normalizedDueDate,
				labels=arrayToList(cleanLabels),
				isBlocked=isBlocked,
				userId=arguments.userId,
				cardId=arguments.cardId,
				workspaceId=arguments.workspaceId
			},
			{ returntype="array" }
		);
		if ( !updateRows.len() ) return { success = false };
		queryExecute(
			"DELETE FROM card_assignee
			 WHERE workspace_id=CAST(:workspaceId AS UUID)
			   AND card_id=CAST(:cardId AS UUID)",
			{ workspaceId=arguments.workspaceId,cardId=arguments.cardId }
		);
		for ( var assigneeId in normalizedAssignees.ids ) {
			queryExecute(
				"INSERT INTO card_assignee(workspace_id,card_id,user_id,assigned_by)
				 VALUES(CAST(:workspaceId AS UUID),CAST(:cardId AS UUID),
				        CAST(:assigneeId AS UUID),CAST(:userId AS UUID))",
				{
					workspaceId=arguments.workspaceId,
					cardId=arguments.cardId,
					assigneeId=assigneeId,
					userId=arguments.userId
				}
			);
		}
		eventVersion = val( updateRows[ 1 ].version );
		recordActivity( arguments.cardId, arguments.userId, "updated" );

		var updatedPayload = {};
		updatedPayload[ "cardTitle" ] = normalizedTitle;
		updatedPayload[ "boardId" ] = access.card.board_id;
		updatedPayload[ "priority" ] = priority;
		updatedPayload[ "assigneeIds" ] = normalizedAssignees.ids;
		updatedPayload[ "assigneeId" ] = normalizedAssignees.ids.len() ? normalizedAssignees.ids[ 1 ] : "";
		updatedPayload[ "dueDate" ] = normalizedDueDate;
		updatedPayload[ "labels" ] = cleanLabels;
		updatedPayload[ "isBlocked" ] = isBlocked;
		eventPublisherService.publish(
			workspaceId = arguments.workspaceId,
			eventType = "card.updated",
			aggregateType = "card",
			aggregateId = arguments.cardId,
			actorId = arguments.userId,
			recipientUserIds = [],
			payload = updatedPayload,
			deduplicationKey = "card.updated:#arguments.cardId#:#eventVersion#"
		);

		if ( wasBlocked != isBlocked ) {
			var blockedEventType = isBlocked ? "card.blocked" : "card.unblocked";
			var blockedPayload = {};
			blockedPayload[ "cardTitle" ] = normalizedTitle;
			blockedPayload[ "boardId" ] = access.card.board_id;
			blockedPayload[ "isBlocked" ] = isBlocked;
			eventPublisherService.publish(
				workspaceId = arguments.workspaceId,
				eventType = blockedEventType,
				aggregateType = "card",
				aggregateId = arguments.cardId,
				actorId = arguments.userId,
				recipientUserIds = [],
				payload = blockedPayload,
				deduplicationKey = "#blockedEventType#:#arguments.cardId#:#eventVersion#"
			);
		}

		if ( assignmentChanged ) {
			var addedAssigneeIds = arrayDifference( normalizedAssignees.ids, previousAssigneeIds );
			var removedAssigneeIds = arrayDifference( previousAssigneeIds, normalizedAssignees.ids );
			var assignedRecipients = recipientsExcept( addedAssigneeIds, arguments.userId );
			var assignedPayload = {};
			assignedPayload[ "cardTitle" ] = normalizedTitle;
			assignedPayload[ "boardId" ] = access.card.board_id;
			assignedPayload[ "previousAssigneeIds" ] = previousAssigneeIds;
			assignedPayload[ "previousAssigneeId" ] = previousAssigneeIds.len() ? previousAssigneeIds[ 1 ] : "";
			assignedPayload[ "assigneeIds" ] = normalizedAssignees.ids;
			assignedPayload[ "assigneeId" ] = normalizedAssignees.ids.len() ? normalizedAssignees.ids[ 1 ] : "";
			assignedPayload[ "addedAssigneeIds" ] = addedAssigneeIds;
			assignedPayload[ "removedAssigneeIds" ] = removedAssigneeIds;
			eventPublisherService.publish(
				workspaceId = arguments.workspaceId,
				eventType = "card.assigned",
				aggregateType = "card",
				aggregateId = arguments.cardId,
				actorId = arguments.userId,
				recipientUserIds = assignedRecipients,
				payload = assignedPayload,
				deduplicationKey = "card.assigned:#arguments.cardId#:#eventVersion#"
			);
		}
		return {
			success=true,
			boardId=access.card.board_id,
			version=eventVersion
		};
	}

	struct function addComment( required string userId, required string workspaceId, required string cardId, required string body ){
		var outcome = { success = false, code = "forbidden" };
		transaction {
			outcome = addCommentLocked(
				userId = arguments.userId,
				workspaceId = arguments.workspaceId,
				cardId = arguments.cardId,
				body = arguments.body
			);
		}
		return outcome;
	}

	private struct function addCommentLocked(
		required string userId,
		required string workspaceId,
		required string cardId,
		required string body
	){
		var normalizedBody = trim( arguments.body );
		if ( !normalizedBody.len() || normalizedBody.len() > 5000 ) {
			return { success = false, code = "invalid_comment" };
		}

		var cardLockRows = queryExecute(
			"SELECT 1
			 FROM card
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			 FOR UPDATE",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardLockRows.len() ) return { success = false, code = "forbidden" };

		var cardRows = queryExecute(
			"SELECT c.title,CAST(c.board_id AS TEXT) AS board_id,
			        access.role AS access_role
			 FROM card c
			 JOIN board b
			   ON b.id=c.board_id
			  AND b.workspace_id=c.workspace_id
			  AND b.is_archived=false
			 JOIN board_column bc
			   ON bc.id=c.column_id
			  AND bc.board_id=c.board_id
			  AND bc.is_archived=false
			 JOIN workspace_member access
			   ON access.workspace_id=c.workspace_id
			  AND access.user_id=CAST(:userId AS UUID)
			 WHERE c.id=CAST(:cardId AS UUID)
			   AND c.workspace_id=CAST(:workspaceId AS UUID)
			   AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))
			 FOR UPDATE OF c
			 FOR SHARE OF access",
			{
				userId = arguments.userId,
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardRows.len() ) return { success = false, code = "forbidden" };
		var card = cardRows[ 1 ];
		if ( card.access_role == "viewer" ) return { success = false, code = "read_only" };

		var commentAssigneeIds = getCardAssigneeIds( arguments.workspaceId, arguments.cardId );
		var commentRecipients = recipientsExcept( commentAssigneeIds, arguments.userId );

		var commentRows = queryExecute(
			"INSERT INTO card_comment(card_id,author_id,body)
			 VALUES(CAST(:card AS UUID),CAST(:user AS UUID),:body)
			 RETURNING CAST(id AS TEXT) AS id",
			{
				card=arguments.cardId,
				user=arguments.userId,
				body=normalizedBody
			},
			{ returntype="array" }
		);
		var commentId = commentRows[ 1 ].id;
		recordActivity( arguments.cardId, arguments.userId, "commented" );
		var commentedPayload = {};
		commentedPayload[ "cardTitle" ] = card.title;
		commentedPayload[ "boardId" ] = card.board_id;
		commentedPayload[ "commentId" ] = commentId;
		commentedPayload[ "commentBody" ] = normalizedBody;
		commentedPayload[ "assigneeIds" ] = commentAssigneeIds;
		commentedPayload[ "assigneeId" ] = commentAssigneeIds.len() ? commentAssigneeIds[ 1 ] : "";
		eventPublisherService.publish(
			workspaceId = arguments.workspaceId,
			eventType = "card.commented",
			aggregateType = "card",
			aggregateId = arguments.cardId,
			actorId = arguments.userId,
			recipientUserIds = commentRecipients,
			payload = commentedPayload,
			deduplicationKey = "card.commented:#commentId#"
		);
		return {success=true};
	}

	struct function archiveCard( required string userId, required string workspaceId, required string cardId ){
		var outcome = { success = false, code = "forbidden" };
		transaction {
			outcome = archiveCardLocked(
				userId = arguments.userId,
				workspaceId = arguments.workspaceId,
				cardId = arguments.cardId
			);
		}
		return outcome;
	}

	private struct function archiveCardLocked(
		required string userId,
		required string workspaceId,
		required string cardId
	){
		var cardLockRows = queryExecute(
			"SELECT 1
			 FROM card
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			 FOR UPDATE",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardLockRows.len() ) return { success = false, code = "forbidden" };

		var cardRows = queryExecute(
			"SELECT c.title,CAST(c.board_id AS TEXT) AS board_id,
			        access.role AS access_role
			 FROM card c
			 JOIN board b
			   ON b.id=c.board_id
			  AND b.workspace_id=c.workspace_id
			  AND b.is_archived=false
			 JOIN board_column bc
			   ON bc.id=c.column_id
			  AND bc.board_id=c.board_id
			  AND bc.is_archived=false
			 JOIN workspace_member access
			   ON access.workspace_id=c.workspace_id
			  AND access.user_id=CAST(:userId AS UUID)
			 WHERE c.id=CAST(:cardId AS UUID)
			   AND c.workspace_id=CAST(:workspaceId AS UUID)
			   AND c.archived_at IS NULL
			   AND (bc.is_hidden_from_members=false OR access.role IN ('owner','admin'))
			 FOR UPDATE OF c
			 FOR SHARE OF access",
			{
				userId = arguments.userId,
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !cardRows.len() ) return { success = false, code = "forbidden" };
		var card = cardRows[ 1 ];
		if ( card.access_role == "viewer" ) return { success = false, code = "read_only" };

		var archivedRows = queryExecute(
			"UPDATE card
			 SET archived_at=now(),updated_at=now()
			 WHERE id=CAST(:cardId AS UUID)
			   AND workspace_id=CAST(:workspaceId AS UUID)
			   AND archived_at IS NULL
			 RETURNING 1",
			{
				cardId = arguments.cardId,
				workspaceId = arguments.workspaceId
			},
			{ returntype = "array" }
		);
		if ( !archivedRows.len() ) return { success = false, code = "forbidden" };

		recordActivity( arguments.cardId, arguments.userId, "archived" );
		var archivedPayload = {};
		archivedPayload[ "cardTitle" ] = card.title;
		archivedPayload[ "boardId" ] = card.board_id;
		eventPublisherService.publish(
			workspaceId = arguments.workspaceId,
			eventType = "card.archived",
			aggregateType = "card",
			aggregateId = arguments.cardId,
			actorId = arguments.userId,
			recipientUserIds = [],
			payload = archivedPayload,
			deduplicationKey = "card.archived:#arguments.cardId#"
		);
		return { success = true, boardId = card.board_id };
	}

	private void function recordActivity(required string cardId,required string userId,required string action){
		queryExecute("INSERT INTO card_activity(card_id,actor_id,action) VALUES(CAST(:card AS UUID),CAST(:user AS UUID),:action)",
			{card=arguments.cardId,user=arguments.userId,action=arguments.action});
	}

	private array function getCardAssigneeIds(
		required string workspaceId,
		required string cardId,
		boolean lockRows=false
	){
		var rows = queryExecute(
			"SELECT CAST(user_id AS TEXT) AS user_id
			 FROM card_assignee
			 WHERE workspace_id=CAST(:workspaceId AS UUID)
			   AND card_id=CAST(:cardId AS UUID)
			 ORDER BY created_at,user_id"
			 & ( arguments.lockRows ? " FOR UPDATE" : "" ),
			{ workspaceId=arguments.workspaceId,cardId=arguments.cardId },
			{ returntype="array" }
		);
		var ids = [];
		for ( var row in rows ) ids.append( row.user_id );
		return ids;
	}

	private struct function normalizeAssigneeIds( required any value ){
		var candidates = [];
		if ( isArray( arguments.value ) ) {
			candidates = arguments.value;
		} else if ( isSimpleValue( arguments.value ) ) {
			candidates = listToArray( toString( arguments.value ) );
		} else {
			return { success=false,ids=[] };
		}
		if ( candidates.len() > 50 ) return { success=false,ids=[] };

		var ids = [];
		for ( var candidate in candidates ) {
			var id = trim( toString( candidate ) );
			if ( !id.len() ) continue;
			if ( !isCanonicalUuid( id ) ) return { success=false,ids=[] };
			if ( !arrayFindNoCase( ids, id ) ) ids.append( lCase( id ) );
		}
		return { success=true,ids=ids };
	}

	private boolean function sameUuidSet( required array leftIds, required array rightIds ){
		if ( arguments.leftIds.len() != arguments.rightIds.len() ) return false;
		for ( var id in arguments.leftIds ) {
			if ( !arrayFindNoCase( arguments.rightIds, id ) ) return false;
		}
		return true;
	}

	private array function arrayDifference( required array sourceIds, required array excludedIds ){
		var result = [];
		for ( var id in arguments.sourceIds ) {
			if ( !arrayFindNoCase( arguments.excludedIds, id ) ) result.append( id );
		}
		return result;
	}

	private array function recipientsExcept( required array userIds, required string actorId ){
		var recipients = [];
		for ( var userId in arguments.userIds ) {
			if (
				compareNoCase( userId, arguments.actorId ) != 0
				&& !arrayFindNoCase( recipients, userId )
			) recipients.append( userId );
		}
		return recipients;
	}

	private boolean function isTruthy( required any value ){
		if ( isBoolean( arguments.value ) ) return arguments.value;
		return listFindNoCase( "1,true,on,yes", trim( toString( arguments.value ) ) ) > 0;
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
				type = "Board.InvalidUuid",
				message = "Could not generate a valid card UUID."
			);
		}
		return left( compact, 8 )
			& "-" & mid( compact, 9, 4 )
			& "-" & mid( compact, 13, 4 )
			& "-" & mid( compact, 17, 4 )
			& "-" & right( compact, 12 );
	}

}
