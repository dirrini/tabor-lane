ALTER TABLE board_column
    ADD COLUMN IF NOT EXISTS is_hidden_from_members BOOLEAN NOT NULL DEFAULT false;
