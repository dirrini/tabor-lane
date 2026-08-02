CREATE UNIQUE INDEX card_workspace_identity_uq
    ON card(workspace_id, id);

CREATE TABLE card_assignee (
    workspace_id UUID NOT NULL,
    card_id UUID NOT NULL,
    user_id UUID NOT NULL,
    assigned_by UUID REFERENCES app_user(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, card_id, user_id),
    FOREIGN KEY (workspace_id, card_id)
        REFERENCES card(workspace_id, id) ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, user_id)
        REFERENCES workspace_member(workspace_id, user_id) ON DELETE CASCADE
);

INSERT INTO card_assignee(workspace_id, card_id, user_id)
SELECT card_record.workspace_id, card_record.id, card_record.assignee_id
FROM card card_record
JOIN workspace_member membership
  ON membership.workspace_id = card_record.workspace_id
 AND membership.user_id = card_record.assignee_id
WHERE card_record.assignee_id IS NOT NULL
ON CONFLICT DO NOTHING;

CREATE INDEX card_assignee_member_lookup_idx
    ON card_assignee(workspace_id, user_id, card_id);

ALTER TABLE card
    ADD COLUMN blocked_at TIMESTAMPTZ,
    ADD COLUMN blocked_by UUID REFERENCES app_user(id) ON DELETE SET NULL;

DROP INDEX IF EXISTS card_workspace_assignee_due_idx;
DROP INDEX IF EXISTS card_analytics_open_idx;

ALTER TABLE card DROP COLUMN assignee_id;

CREATE INDEX card_workspace_open_due_idx
    ON card(workspace_id, due_at, updated_at DESC)
    WHERE archived_at IS NULL;

CREATE INDEX card_board_content_revision_idx
    ON card(board_id, updated_at DESC)
    WHERE archived_at IS NULL;

CREATE INDEX board_column_content_revision_idx
    ON board_column(board_id, updated_at DESC)
    WHERE is_archived = false;

CREATE INDEX card_analytics_open_idx
    ON card(workspace_id, board_id, column_id)
    WHERE archived_at IS NULL AND completed_at IS NULL;
