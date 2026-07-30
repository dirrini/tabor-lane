ALTER TABLE board_column
    ADD COLUMN IF NOT EXISTS is_archived BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS board_column_active_position_idx
    ON board_column(board_id, position)
    WHERE is_archived = false;
