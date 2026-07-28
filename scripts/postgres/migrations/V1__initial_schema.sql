CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE workspace (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(160) NOT NULL,
    slug VARCHAR(100) NOT NULL UNIQUE,
    plan VARCHAR(20) NOT NULL DEFAULT 'free'
        CHECK (plan IN ('free', 'premium')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app_user (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(320) NOT NULL UNIQUE,
    display_name VARCHAR(160) NOT NULL,
    password_hash TEXT,
    locale VARCHAR(10) NOT NULL DEFAULT 'en_US',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE workspace_member (
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'member'
        CHECK (role IN ('owner', 'admin', 'member', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (workspace_id, user_id)
);

CREATE TABLE board (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    name VARCHAR(160) NOT NULL,
    description TEXT,
    is_archived BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX board_workspace_idx ON board(workspace_id, is_archived);

CREATE TABLE board_column (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    board_id UUID NOT NULL REFERENCES board(id) ON DELETE CASCADE,
    name VARCHAR(120) NOT NULL,
    position NUMERIC(20, 10) NOT NULL,
    wip_limit INTEGER CHECK (wip_limit IS NULL OR wip_limit > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (board_id, position)
);

CREATE TABLE card (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    board_id UUID NOT NULL REFERENCES board(id) ON DELETE CASCADE,
    column_id UUID NOT NULL REFERENCES board_column(id) ON DELETE RESTRICT,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    position NUMERIC(20, 10) NOT NULL,
    custom_fields JSONB NOT NULL DEFAULT '{}'::jsonb,
    due_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    version INTEGER NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    archived_at TIMESTAMPTZ
);

CREATE INDEX card_board_column_position_idx
    ON card(board_id, column_id, position)
    WHERE archived_at IS NULL;
CREATE INDEX card_custom_fields_gin_idx ON card USING GIN(custom_fields);

CREATE TABLE card_transition (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    card_id UUID NOT NULL REFERENCES card(id) ON DELETE CASCADE,
    from_column_id UUID REFERENCES board_column(id) ON DELETE SET NULL,
    to_column_id UUID NOT NULL REFERENCES board_column(id) ON DELETE RESTRICT,
    actor_user_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    correlation_id UUID NOT NULL DEFAULT gen_random_uuid()
);

CREATE INDEX card_transition_metrics_idx
    ON card_transition(workspace_id, card_id, occurred_at);

CREATE TABLE attachment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    card_id UUID NOT NULL REFERENCES card(id) ON DELETE CASCADE,
    object_key VARCHAR(1024) NOT NULL UNIQUE,
    original_filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(255) NOT NULL,
    size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
    checksum_sha256 CHAR(64),
    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'uploaded', 'scanning', 'available', 'rejected', 'deleted')),
    uploaded_by UUID REFERENCES app_user(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX attachment_card_idx ON attachment(card_id)
    WHERE deleted_at IS NULL;

CREATE TABLE outbox_event (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspace(id) ON DELETE CASCADE,
    event_type VARCHAR(160) NOT NULL,
    aggregate_type VARCHAR(80) NOT NULL,
    aggregate_id UUID NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX outbox_pending_idx ON outbox_event(created_at)
    WHERE processed_at IS NULL;

