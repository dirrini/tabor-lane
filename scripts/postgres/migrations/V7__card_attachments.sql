CREATE TABLE IF NOT EXISTS attachment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    card_id UUID NOT NULL REFERENCES card(id) ON DELETE CASCADE,
    object_key TEXT NOT NULL UNIQUE,
    original_filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(255) NOT NULL DEFAULT 'application/octet-stream',
    size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'available', 'rejected', 'deleted')),
    uploaded_by UUID REFERENCES app_user(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS attachment_card_idx
    ON attachment(card_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS attachment_workspace_quota_idx
    ON attachment(workspace_id, status)
    WHERE deleted_at IS NULL;
