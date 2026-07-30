CREATE TABLE board_column_preference (
    user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    column_id UUID NOT NULL REFERENCES board_column(id) ON DELETE CASCADE,
    width_px INTEGER NOT NULL DEFAULT 280 CHECK (width_px BETWEEN 240 AND 1200),
    is_collapsed BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, column_id)
);

CREATE INDEX board_column_preference_column_idx
    ON board_column_preference(column_id);
