ALTER TABLE app_user
    ADD COLUMN IF NOT EXISTS last_workspace_id UUID REFERENCES workspace(id) ON DELETE SET NULL;

UPDATE app_user user_account
SET last_workspace_id = first_membership.workspace_id
FROM (
    SELECT DISTINCT ON (user_id) user_id, workspace_id
    FROM workspace_member
    ORDER BY user_id, created_at, workspace_id
) first_membership
WHERE first_membership.user_id = user_account.id
  AND user_account.last_workspace_id IS NULL;

CREATE TABLE IF NOT EXISTS my_work_filter_preference (
    workspace_id UUID NOT NULL,
    user_id UUID NOT NULL,
    search_query VARCHAR(100) NOT NULL DEFAULT '',
    board_id UUID REFERENCES board(id) ON DELETE SET NULL,
    priority_filter VARCHAR(20) NOT NULL DEFAULT ''
        CHECK (priority_filter IN ('', 'none', 'low', 'medium', 'high', 'urgent')),
    due_filter VARCHAR(20) NOT NULL DEFAULT 'all'
        CHECK (due_filter IN ('all', 'overdue', 'today', 'upcoming', 'no_due', 'completed')),
    sort_order VARCHAR(20) NOT NULL DEFAULT 'due'
        CHECK (sort_order IN ('due', 'priority', 'updated')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, user_id),
    FOREIGN KEY (workspace_id, user_id)
        REFERENCES workspace_member(workspace_id, user_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_avatar (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL UNIQUE,
    original_filename VARCHAR(255) NOT NULL,
    source_content_type VARCHAR(32) NOT NULL,
    source_size_bytes BIGINT NOT NULL CHECK (source_size_bytes > 0),
    content_type VARCHAR(32) NOT NULL DEFAULT 'image/jpeg',
    size_bytes BIGINT NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
    width_px INTEGER,
    height_px INTEGER,
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'available', 'rejected', 'deleted')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS user_avatar_available_user_idx
    ON user_avatar(user_id)
    WHERE status = 'available' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS user_avatar_pending_cleanup_idx
    ON user_avatar(created_at)
    WHERE status = 'pending' AND deleted_at IS NULL;
