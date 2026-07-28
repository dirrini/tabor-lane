ALTER TABLE app_user
    ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS auth_token (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    purpose VARCHAR(30) NOT NULL
        CHECK (purpose IN ('email_verification', 'password_reset')),
    token_hash CHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS auth_token_lookup_idx
    ON auth_token(token_hash, purpose, expires_at)
    WHERE consumed_at IS NULL;

CREATE TABLE IF NOT EXISTS workspace_invitation (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    email VARCHAR(320) NOT NULL,
    role VARCHAR(20) NOT NULL DEFAULT 'member'
        CHECK (role IN ('admin', 'member', 'viewer')),
    token_hash CHAR(64) NOT NULL UNIQUE,
    invited_by UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS workspace_invitation_pending_idx
    ON workspace_invitation(workspace_id, lower(email))
    WHERE accepted_at IS NULL;

CREATE INDEX IF NOT EXISTS workspace_invitation_token_idx
    ON workspace_invitation(token_hash, expires_at)
    WHERE accepted_at IS NULL;
