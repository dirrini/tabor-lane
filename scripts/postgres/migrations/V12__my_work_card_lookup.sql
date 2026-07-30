CREATE INDEX card_workspace_assignee_due_idx
    ON card(workspace_id, assignee_id, due_at, updated_at DESC)
    WHERE archived_at IS NULL AND assignee_id IS NOT NULL;
