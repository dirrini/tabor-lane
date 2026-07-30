ALTER TABLE card
    ADD COLUMN IF NOT EXISTS priority VARCHAR(20) NOT NULL DEFAULT 'none'
        CHECK (priority IN ('none', 'low', 'medium', 'high', 'urgent')),
    ADD COLUMN IF NOT EXISTS assignee_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS labels TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

CREATE TABLE IF NOT EXISTS card_comment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id UUID NOT NULL REFERENCES card(id) ON DELETE CASCADE,
    author_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS card_comment_card_idx ON card_comment(card_id, created_at);

CREATE TABLE IF NOT EXISTS card_activity (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id UUID NOT NULL REFERENCES card(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES app_user(id) ON DELETE SET NULL,
    action VARCHAR(40) NOT NULL,
    details JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS card_activity_card_idx ON card_activity(card_id, created_at DESC);
