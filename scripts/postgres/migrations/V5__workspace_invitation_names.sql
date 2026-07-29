ALTER TABLE workspace_invitation
    ADD COLUMN IF NOT EXISTS invitee_name VARCHAR(160);
