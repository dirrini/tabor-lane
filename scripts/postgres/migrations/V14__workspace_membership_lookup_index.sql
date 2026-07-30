CREATE INDEX IF NOT EXISTS workspace_member_user_idx
    ON workspace_member(user_id, created_at, workspace_id);
