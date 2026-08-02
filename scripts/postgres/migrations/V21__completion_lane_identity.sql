ALTER TABLE board_column
    ADD COLUMN is_completion_lane BOOLEAN NOT NULL DEFAULT false;

WITH ranked_lanes AS (
    SELECT lane.id,
           ROW_NUMBER() OVER (
               PARTITION BY lane.board_id
               ORDER BY lane.is_hidden_from_members ASC,
                        lane.position DESC,
                        lane.created_at DESC,
                        lane.id DESC
           ) AS completion_rank
    FROM board_column lane
    WHERE lane.is_archived = false
)
UPDATE board_column lane
SET is_completion_lane = true
FROM ranked_lanes ranked
WHERE lane.id = ranked.id
  AND ranked.completion_rank = 1;

CREATE UNIQUE INDEX board_column_active_completion_lane_uq
    ON board_column(board_id)
    WHERE is_completion_lane = true AND is_archived = false;
