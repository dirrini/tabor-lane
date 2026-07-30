ALTER TABLE board_column
    ADD COLUMN IF NOT EXISTS color VARCHAR(20) NOT NULL DEFAULT 'red'
        CHECK (color IN ('red', 'blue', 'amber', 'green', 'purple', 'slate')),
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS board_column_board_position_idx
    ON board_column(board_id, position);
