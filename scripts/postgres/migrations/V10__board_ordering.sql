ALTER TABLE board
    ADD COLUMN IF NOT EXISTS position NUMERIC(20, 10) NOT NULL DEFAULT 0;

WITH ranked AS (
    SELECT id, ROW_NUMBER() OVER (PARTITION BY workspace_id ORDER BY created_at, name, id) AS new_position
    FROM board
)
UPDATE board b
SET position = ranked.new_position
FROM ranked
WHERE ranked.id = b.id;

CREATE INDEX IF NOT EXISTS board_workspace_position_idx
    ON board(workspace_id, is_archived, position);
