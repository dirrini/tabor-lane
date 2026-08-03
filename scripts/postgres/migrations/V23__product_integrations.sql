ALTER TABLE outbox_event
    ADD CONSTRAINT outbox_event_workspace_identity_uq
        UNIQUE (workspace_id, id);

CREATE TABLE api_token (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    subject_user_id UUID NOT NULL,
    name VARCHAR(120) NOT NULL
        CHECK (length(btrim(name)) BETWEEN 1 AND 120),
    public_id CHAR(16) NOT NULL UNIQUE
        CHECK (public_id ~ '^[0-9a-f]{16}$'),
    token_hash CHAR(64) NOT NULL UNIQUE
        CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    scopes JSONB NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    revoked_by UUID REFERENCES app_user(id) ON DELETE SET NULL,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    FOREIGN KEY (workspace_id, subject_user_id)
        REFERENCES workspace_member(workspace_id, user_id) ON DELETE CASCADE,
    CONSTRAINT api_token_scopes_ck CHECK (
        jsonb_typeof(scopes) = 'array'
        AND jsonb_array_length(scopes) BETWEEN 1 AND 5
        AND scopes <@ '[
            "boards:read",
            "cards:read",
            "cards:create",
            "cards:update",
            "cards:move"
        ]'::jsonb
    ),
    CONSTRAINT api_token_expiration_ck CHECK (
        expires_at > created_at
        AND expires_at <= created_at + INTERVAL '365 days'
    ),
    CONSTRAINT api_token_revocation_ck CHECK (
        revoked_at IS NULL OR revoked_at >= created_at
    )
);

CREATE INDEX api_token_workspace_active_idx
    ON api_token(workspace_id, expires_at, created_at, id)
    WHERE revoked_at IS NULL;

CREATE TABLE webhook_endpoint (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    name VARCHAR(120) NOT NULL
        CHECK (length(btrim(name)) BETWEEN 1 AND 120),
    url VARCHAR(2048) NOT NULL
        CHECK (length(btrim(url)) BETWEEN 1 AND 2048),
    event_types JSONB NOT NULL,
    secret_ciphertext TEXT NOT NULL
        CHECK (length(secret_ciphertext) > 0),
    secret_nonce VARCHAR(64) NOT NULL
        CHECK (length(secret_nonce) > 0),
    secret_key_version SMALLINT NOT NULL DEFAULT 1
        CHECK (secret_key_version > 0),
    secret_hint VARCHAR(12) NOT NULL
        CHECK (length(secret_hint) BETWEEN 4 AND 12),
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    consecutive_failures INTEGER NOT NULL DEFAULT 0
        CHECK (consecutive_failures >= 0),
    last_delivery_at TIMESTAMPTZ,
    last_success_at TIMESTAMPTZ,
    last_failure_at TIMESTAMPTZ,
    created_by UUID REFERENCES app_user(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,

    UNIQUE (workspace_id, id),
    CONSTRAINT webhook_endpoint_event_types_ck CHECK (
        jsonb_typeof(event_types) = 'array'
        AND jsonb_array_length(event_types) BETWEEN 1 AND 10
        AND event_types <@ '[
            "card.created",
            "card.moved",
            "card.reordered",
            "card.updated",
            "card.assigned",
            "card.archived",
            "card.blocked",
            "card.unblocked",
            "card.completed",
            "card.reopened"
        ]'::jsonb
    ),
    CONSTRAINT webhook_endpoint_deleted_ck CHECK (
        deleted_at IS NULL OR is_enabled = false
    )
);

CREATE INDEX webhook_endpoint_workspace_active_idx
    ON webhook_endpoint(workspace_id, created_at, id)
    WHERE deleted_at IS NULL;

CREATE INDEX webhook_endpoint_workspace_enabled_idx
    ON webhook_endpoint(workspace_id, id)
    WHERE is_enabled = true AND deleted_at IS NULL;

CREATE TABLE webhook_delivery (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    endpoint_id UUID NOT NULL,
    outbox_event_id UUID,
    event_id UUID NOT NULL,
    event_type VARCHAR(160) NOT NULL
        CHECK (event_type IN (
            'card.created',
            'card.moved',
            'card.reordered',
            'card.updated',
            'card.assigned',
            'card.archived',
            'card.blocked',
            'card.unblocked',
            'card.completed',
            'card.reopened',
            'integration.test'
        )),
    event_version SMALLINT NOT NULL DEFAULT 1
        CHECK (event_version > 0),
    envelope JSONB NOT NULL
        CHECK (jsonb_typeof(envelope) = 'object'),
    request_body TEXT NOT NULL
        CHECK (length(request_body) > 0),
    attempts INTEGER NOT NULL DEFAULT 0
        CHECK (attempts >= 0),
    available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_at TIMESTAMPTZ,
    claimed_by VARCHAR(160),
    delivered_at TIMESTAMPTZ,
    failed_at TIMESTAMPTZ,
    last_http_status INTEGER
        CHECK (last_http_status IS NULL OR last_http_status BETWEEN 100 AND 599),
    last_error VARCHAR(4000),
    last_response_excerpt VARCHAR(4000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (workspace_id, id),
    UNIQUE (endpoint_id, event_id),
    FOREIGN KEY (workspace_id, endpoint_id)
        REFERENCES webhook_endpoint(workspace_id, id) ON DELETE CASCADE,
    FOREIGN KEY (workspace_id, outbox_event_id)
        REFERENCES outbox_event(workspace_id, id) ON DELETE CASCADE,
    CONSTRAINT webhook_delivery_claim_ck CHECK (
        (claimed_at IS NULL AND claimed_by IS NULL)
        OR (claimed_at IS NOT NULL AND claimed_by IS NOT NULL)
    ),
    CONSTRAINT webhook_delivery_outcome_ck CHECK (
        NOT (delivered_at IS NOT NULL AND failed_at IS NOT NULL)
    )
);

CREATE INDEX webhook_delivery_ready_idx
    ON webhook_delivery(available_at, created_at, id)
    WHERE delivered_at IS NULL AND failed_at IS NULL;

CREATE INDEX webhook_delivery_stale_claim_idx
    ON webhook_delivery(claimed_at, attempts)
    WHERE delivered_at IS NULL AND failed_at IS NULL AND claimed_at IS NOT NULL;

CREATE INDEX webhook_delivery_endpoint_history_idx
    ON webhook_delivery(endpoint_id, created_at DESC, id DESC);

CREATE TABLE webhook_delivery_attempt (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL,
    delivery_id UUID NOT NULL,
    attempt_no INTEGER NOT NULL CHECK (attempt_no > 0),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
    http_status INTEGER
        CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
    outcome VARCHAR(20) NOT NULL
        CHECK (outcome IN ('success', 'retry', 'failed')),
    error_message VARCHAR(4000),
    response_excerpt VARCHAR(4000),

    UNIQUE (delivery_id, attempt_no),
    FOREIGN KEY (workspace_id, delivery_id)
        REFERENCES webhook_delivery(workspace_id, id) ON DELETE CASCADE,
    CONSTRAINT webhook_delivery_attempt_completed_ck CHECK (
        completed_at IS NULL OR completed_at >= started_at
    )
);

CREATE INDEX webhook_delivery_attempt_history_idx
    ON webhook_delivery_attempt(delivery_id, attempt_no DESC);
