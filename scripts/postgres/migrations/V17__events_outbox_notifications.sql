ALTER TABLE outbox_event
    ADD COLUMN actor_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
    ADD COLUMN recipient_user_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN deduplication_key VARCHAR(255),
    ADD COLUMN event_version SMALLINT NOT NULL DEFAULT 1,
    ADD COLUMN correlation_id UUID NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ADD COLUMN claimed_at TIMESTAMPTZ,
    ADD COLUMN claimed_by VARCHAR(160),
    ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN last_error TEXT,
    ADD COLUMN failed_at TIMESTAMPTZ;

ALTER TABLE outbox_event
    ADD CONSTRAINT outbox_event_recipient_user_ids_array_check
        CHECK (jsonb_typeof(recipient_user_ids) = 'array'),
    ADD CONSTRAINT outbox_event_attempts_check
        CHECK (attempts >= 0),
    ADD CONSTRAINT outbox_event_version_check
        CHECK (event_version > 0),
    ADD CONSTRAINT outbox_event_claim_pair_check
        CHECK (
            (claimed_at IS NULL AND claimed_by IS NULL)
            OR (claimed_at IS NOT NULL AND claimed_by IS NOT NULL)
        );

CREATE UNIQUE INDEX outbox_event_workspace_deduplication_idx
    ON outbox_event(workspace_id, deduplication_key)
    WHERE deduplication_key IS NOT NULL;

CREATE INDEX outbox_event_ready_idx
    ON outbox_event(available_at, created_at, id)
    WHERE processed_at IS NULL AND failed_at IS NULL;

CREATE INDEX outbox_event_stale_claim_idx
    ON outbox_event(claimed_at, attempts)
    WHERE processed_at IS NULL AND failed_at IS NULL AND claimed_at IS NOT NULL;

DROP INDEX IF EXISTS outbox_pending_idx;

CREATE TABLE app_notification (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID REFERENCES outbox_event(id) ON DELETE SET NULL,
    workspace_id UUID NOT NULL,
    user_id UUID NOT NULL,
    notification_type VARCHAR(160) NOT NULL,
    actor_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
    aggregate_type VARCHAR(80) NOT NULL,
    aggregate_id UUID NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ,
    FOREIGN KEY (workspace_id, user_id)
        REFERENCES workspace_member(workspace_id, user_id) ON DELETE CASCADE,
    UNIQUE (event_id, user_id)
);

CREATE INDEX app_notification_user_created_idx
    ON app_notification(workspace_id, user_id, created_at DESC, id DESC);

CREATE INDEX app_notification_user_unread_idx
    ON app_notification(workspace_id, user_id, created_at DESC, id DESC)
    WHERE read_at IS NULL;
