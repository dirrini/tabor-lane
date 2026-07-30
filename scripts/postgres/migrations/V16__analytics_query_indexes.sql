CREATE INDEX IF NOT EXISTS card_analytics_completed_idx
    ON card(workspace_id, completed_at)
    WHERE completed_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS card_analytics_open_idx
    ON card(workspace_id, board_id, column_id, assignee_id)
    WHERE archived_at IS NULL AND completed_at IS NULL;

CREATE INDEX IF NOT EXISTS card_transition_workspace_occurred_idx
    ON card_transition(workspace_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS card_transition_current_lane_idx
    ON card_transition(workspace_id, card_id, to_column_id, occurred_at DESC);
