CREATE UNIQUE INDEX IF NOT EXISTS board_workspace_identity_uq
    ON board(workspace_id, id);

CREATE UNIQUE INDEX IF NOT EXISTS board_column_board_identity_uq
    ON board_column(board_id, id);

CREATE TABLE automation_rule (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    board_id UUID NOT NULL,
    target_column_id UUID NOT NULL,
    recipient_user_id UUID NOT NULL,
    name VARCHAR(160) NOT NULL
        CHECK (length(btrim(name)) BETWEEN 1 AND 160),
    trigger_type VARCHAR(40) NOT NULL DEFAULT 'card_moved_to_lane'
        CHECK (trigger_type = 'card_moved_to_lane'),
    action_type VARCHAR(40) NOT NULL DEFAULT 'notify_user'
        CHECK (action_type = 'notify_user'),
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    run_count BIGINT NOT NULL DEFAULT 0 CHECK (run_count >= 0),
    last_triggered_at TIMESTAMPTZ,
    created_by UUID REFERENCES app_user(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,

    FOREIGN KEY (workspace_id, board_id)
        REFERENCES board(workspace_id, id) ON DELETE CASCADE,
    FOREIGN KEY (board_id, target_column_id)
        REFERENCES board_column(board_id, id) ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, recipient_user_id)
        REFERENCES workspace_member(workspace_id, user_id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX automation_rule_identity_uq
    ON automation_rule(workspace_id, target_column_id, recipient_user_id)
    WHERE deleted_at IS NULL;

CREATE INDEX automation_rule_match_idx
    ON automation_rule(workspace_id, board_id, target_column_id)
    WHERE is_enabled AND deleted_at IS NULL;

CREATE TABLE automation_execution (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    automation_rule_id UUID NOT NULL REFERENCES automation_rule(id) ON DELETE CASCADE,
    event_id UUID NOT NULL REFERENCES outbox_event(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    recipient_user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (automation_rule_id, event_id)
);

CREATE INDEX automation_execution_workspace_idx
    ON automation_execution(workspace_id, executed_at DESC);
