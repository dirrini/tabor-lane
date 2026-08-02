UPDATE board_column
SET is_completion_lane = false,
    updated_at = clock_timestamp()
WHERE is_archived = true
  AND is_completion_lane = true;

UPDATE board_column
SET is_hidden_from_members = false,
    updated_at = clock_timestamp()
WHERE is_archived = false
  AND is_completion_lane = true
  AND is_hidden_from_members = true;

UPDATE card card_record
SET completed_at = NULL,
    version = card_record.version + 1,
    updated_at = clock_timestamp()
FROM board_column lane
WHERE lane.id = card_record.column_id
  AND lane.board_id = card_record.board_id
  AND lane.is_archived = false
  AND lane.is_hidden_from_members = false
  AND lane.is_completion_lane = false
  AND card_record.archived_at IS NULL
  AND card_record.completed_at IS NOT NULL;

UPDATE card card_record
SET completed_at = COALESCE(card_record.completed_at, card_record.updated_at, card_record.created_at),
    started_at = COALESCE(card_record.started_at, card_record.created_at),
    version = card_record.version + 1,
    updated_at = clock_timestamp()
FROM board_column lane
WHERE lane.id = card_record.column_id
  AND lane.board_id = card_record.board_id
  AND lane.is_archived = false
  AND lane.is_completion_lane = true
  AND card_record.archived_at IS NULL
  AND card_record.completed_at IS NULL;

ALTER TABLE board_column
    ADD CONSTRAINT board_column_completion_lane_visible_ck
    CHECK (NOT (is_completion_lane AND is_hidden_from_members));
