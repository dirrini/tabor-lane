ALTER TABLE workspace
    ADD COLUMN timezone VARCHAR(64) NOT NULL DEFAULT 'UTC',
    ADD COLUMN default_locale VARCHAR(10),
    ADD COLUMN invitation_policy VARCHAR(20) NOT NULL DEFAULT 'owner_admin',
    ADD COLUMN board_creation_policy VARCHAR(20) NOT NULL DEFAULT 'owner_admin';

UPDATE app_user
SET locale = CASE WHEN lower(locale) = 'pt_br' THEN 'pt_BR' ELSE 'en_US' END
WHERE locale NOT IN ('en_US', 'pt_BR');

ALTER TABLE app_user
    ADD CONSTRAINT app_user_locale_ck CHECK (locale IN ('en_US', 'pt_BR'));

UPDATE workspace workspace_record
SET default_locale = COALESCE(
    (
        SELECT user_account.locale
        FROM workspace_member membership
        JOIN app_user user_account ON user_account.id = membership.user_id
        WHERE membership.workspace_id = workspace_record.id
          AND membership.role = 'owner'
        ORDER BY membership.created_at, membership.user_id
        LIMIT 1
    ),
    'en_US'
)
WHERE default_locale IS NULL;

ALTER TABLE workspace
    ALTER COLUMN default_locale SET DEFAULT 'en_US',
    ALTER COLUMN default_locale SET NOT NULL,
    ADD CONSTRAINT workspace_default_locale_ck
        CHECK (default_locale IN ('en_US', 'pt_BR')),
    ADD CONSTRAINT workspace_invitation_policy_ck
        CHECK (invitation_policy IN ('owner_admin', 'owner_only')),
    ADD CONSTRAINT workspace_board_creation_policy_ck
        CHECK (board_creation_policy IN ('owner_admin', 'owner_only'));

CREATE UNIQUE INDEX workspace_single_owner_uq
    ON workspace_member(workspace_id)
    WHERE role = 'owner';
