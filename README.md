# Tabor Lane

Tabor Lane is a modular Kanban workspace for clear, connected work. This
repository contains the first product foundation: a bilingual server-rendered
landing page, application preview, PostgreSQL schema and local S3-compatible
attachment storage.

The application includes registration, email verification, password recovery,
login and workspace invitations. Every independent account creates a Free
workspace, links the user as its owner and provisions an initial board. Invited
accounts join the existing workspace with their assigned role. Authenticated
users can manage multiple boards and lanes, create complete cards and move them
through workflows with changes persisted in PostgreSQL. Domain changes are
published through a transactional outbox and delivered to the in-app
notification center without coupling card writes to external services. Premium
workspace owners and admins can create lane-entry automations that notify a
selected member when a card reaches a configured lane. Workspace settings let
privileged users maintain identity and regional defaults, while owner-controlled
security policies govern invitations, board creation and ownership transfers.

## Technology

- Lucee 6 and ColdBox 7
- cbI18n resource bundles for English and Brazilian Portuguese
- PostgreSQL 17
- MinIO for local attachment storage
- Docker Compose for the complete development environment
- GitHub Actions for CI and multi-platform OCI deployment
- Flyway migrations for local and managed PostgreSQL
- PostgreSQL transactional outbox with a ColdBox scheduled processor
- Neon PostgreSQL for production
- Upstash Redis for distributed rate limiting
- Brevo for transactional email
- Google OpenID Connect for optional social login
- Stripe for subscriptions and billing
- Cloudflare R2 for production attachment storage

## Run locally

Requirements: Docker Desktop with Docker Compose. Running the functional smoke test
locally also requires Git Bash and Node.js 18 or newer.

```powershell
Copy-Item .env.example .env
docker compose up --build --wait
```

Open:

- Product: <http://localhost:8090>
- Workspace preview: <http://localhost:8090/app>
- MinIO Console: <http://localhost:9001>
- Readiness: <http://localhost:8090/health/ready>

Development exposes safe verification and password-reset links in the UI when
Brevo is not configured. Production never exposes authentication tokens.

## Production architecture

The OCI VM runs only Nginx and the Lucee/ColdBox application container.
PostgreSQL is hosted by Neon, rate limiting by Upstash, attachments by
Cloudflare R2, subscriptions by Stripe and transactional email by Brevo.

Use the pooled Neon hostname and require TLS. Production configuration includes:

- `DB_JDBC_URL` for Flyway, including `sslmode=require`
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `DB_SSL_MODE=require`
- `APP_BASE_URL`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`
- `STRIPE_PRICE_PREMIUM_MONTHLY`, `STRIPE_PRICE_PREMIUM_YEARLY`
- `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, `BREVO_SENDER_NAME`
- `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`
- `OUTBOX_PROCESSING_ENABLED`, `OUTBOX_BATCH_SIZE`, `OUTBOX_INTERVAL_SECONDS`
- `OUTBOX_MAX_ATTEMPTS`, `OUTBOX_CLAIM_TIMEOUT_SECONDS`
- `WEBHOOK_SECRET_ENCRYPTION_KEY` (Base64-encoded 32-byte key)

Database migrations live in `scripts/postgres/migrations`. They run before the
application starts in both development and production.

Google login uses the backend Authorization Code flow with the exact callback
URI `${APP_BASE_URL}/auth/google/callback`. Only verified Google email addresses
are accepted. If that email already belongs to an account, Google is linked to
the existing user instead of creating a duplicate.

Premium billing uses Stripe-hosted Checkout and the Customer Portal. Stripe
webhooks are verified and processed idempotently at `/stripe/webhook`; only
confirmed subscription status events change the workspace plan.

For local webhook forwarding, the Stripe CLI runs as an opt-in Compose service:

```powershell
docker compose --profile stripe up stripe-cli
```

Copy the `whsec_` signing secret printed by that container to
`STRIPE_WEBHOOK_SECRET` in `.env`, then recreate `app` while keeping
`stripe-cli` running.

Stop and preserve data:

```powershell
docker compose down
```

Stop and remove local database and object data:

```powershell
docker compose down --volumes
```

## Internationalization

UI copy lives in:

```text
src/includes/i18n/main_en_US.json
src/includes/i18n/main_pt_BR.json
```

The selected locale is stored in a cookie by cbI18n. Locale routes are
`/locale/en_US` and `/locale/pt_BR`.

## Interface conventions

Interface icons must use SVG assets from `src/resources/icons.svg`. Do not use
Unicode characters, emoji or icon fonts as visual icons. The Tabor Lane brand
mark and favicon always include the Tabor `T`.

## Attachments

Development uses a private MinIO bucket created by `minio-init`. Production can
replace MinIO with Cloudflare R2 by changing only the `STORAGE_*` environment
variables. Files belong in object storage; attachment metadata and permissions
belong in PostgreSQL.

Uploads and downloads use short-lived S3 presigned URLs, so file contents do not
pass through the Lucee container. Configure the R2 bucket CORS policy to allow
the production application origin with `PUT`, `GET` and `HEAD`; keep the bucket
private. `STORAGE_PUBLIC_ENDPOINT` must be the browser-reachable R2 S3 endpoint
and can use the same value as `STORAGE_ENDPOINT` in production.

Free workspaces can store files up to 10 MB each and 100 MB in total. Premium
workspaces can store files up to 50 MB each and 5 GB in total.

## Boards and lanes

Workspace owners and admins can create boards from simple Kanban, software,
marketing and personal templates. Boards support editing, ordering, archiving
and restoration. Lanes support names, colors, ordering and enforceable WIP
limits. A lane with active cards cannot be removed, and removal is implemented
as a soft delete to preserve transition history.

Free workspaces can keep up to 3 active boards. Premium workspaces have no
active-board limit.

## Real-time board synchronization

Free workspaces revalidate the visible board periodically and whenever the tab
becomes active. Premium workspaces additionally open an authenticated
Server-Sent Events stream. The stream carries only the opaque board revision;
when it changes, the browser fetches and replaces only `#workspace-main`, while
preserving horizontal scroll and avoiding refreshes during an active edit or
drag operation. Regular revision polling remains as a fallback.

The current Lucee implementation keeps each stream open for about 22 seconds
and checks the shared PostgreSQL revision every 2 seconds. This works across
application instances without sticky sessions and is appropriate for the first
single-VM deployment. Each application process accepts at most 20 simultaneous
streams and 4 per user; excess clients transparently keep using revision
polling. Connection starts are rate-limited before database access, and the
limiter fails closed for this endpoint in production if Upstash is unavailable.
Monitor Lucee request-thread usage and managed PostgreSQL read load as Premium
concurrency grows; a dedicated realtime gateway or event broker is the later
scaling path.

The Nginx location that proxies the SSE endpoint must disable buffering and use
a timeout longer than the application stream:

```nginx
location ~ ^/app/boards/[0-9a-f-]+/events$ {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_cache off;
    gzip off;
    proxy_read_timeout 40s;
}
```

## Workspace settings

Owners and admins can update the workspace name, unique slug, reporting time
zone and default language. The time zone is applied to Analytics date boundaries,
and the default language is used for new board templates and invitation messages.

Only the current owner can decide whether administrators may invite members or
create boards. Ownership can be transferred to another verified member after
the current owner's password is confirmed. The transfer is transactional and a
database constraint prevents more than one owner in the same workspace. The
previous owner becomes an administrator immediately; subscription management
remains exclusive to the current owner.

## Events and notifications

Supported card lifecycle and workspace-membership changes write domain events
to `outbox_event` in the same PostgreSQL transaction as the business operation.
A ColdBox scheduled task claims pending events with row-level locking, creates
idempotent in-app notifications and retries transient failures with exponential
backoff. The claim protocol supports more than one application instance without
processing the same event concurrently.

The notification center is workspace-scoped, supports unread filtering and
read state, and rechecks current membership and hidden-lane visibility before
returning any card data. Set `OUTBOX_PROCESSING_ENABLED=false` on an application
instance only when another instance is responsible for processing the shared
outbox.

## Product integrations

Workspace owners and administrators can manage server-to-server credentials at
`/app/settings/integrations`. API tokens are shown only once, stored only as a
SHA-256 hash and revalidate the creator's current membership, role and verified
email on every request. Free workspaces can keep 1 active token and Premium
workspaces can keep 10.

The first API version exposes:

- `GET /api/v1/boards` and `GET /api/v1/boards/:boardId`
- `GET /api/v1/boards/:boardId/cards` and `GET /api/v1/cards/:cardId`
- `POST /api/v1/cards`
- `PATCH /api/v1/cards/:cardId`
- `POST /api/v1/cards/:cardId/move`

Credentials use Bearer authentication and granular `boards:read`, `cards:read`,
`cards:create`, `cards:update` and `cards:move` scopes. The API never falls back
to a browser session and applies the same workspace, role, hidden-lane, WIP and
optimistic-lock rules as the application.

Webhook endpoint registration, encrypted signing secrets and the durable
delivery queue are part of this first foundation. The outbound HTTP dispatcher
is intentionally not enabled yet; activating transmission to registered
third-party endpoints requires an explicit product authorization and a final
payload/privacy review.

## Automations

The first automation trigger is `card moved to lane` and its action is `notify
workspace member`. Rules are evaluated by the claimed outbox worker before the
domain event is delivered, so the movement and its automated notification share
the same retry and idempotency guarantees. Executions are recorded once per
rule and event.

Workspace members can view rules that do not expose hidden lanes. Only owners
and admins can manage them. Creating or enabling rules requires Premium;
disabling and removing existing rules remains available after a downgrade. A
workspace can keep up to 50 rules.

## Delivery

`ci.yml` validates translations, builds the application, starts the complete
stack and checks application, PostgreSQL and MinIO health. Its functional smoke
test also covers account lifecycle, cards, attachments, members, boards, lanes,
plan limits, archiving, WIP enforcement, workspace settings, security policies,
ownership transfers, lane-entry automations, the transactional outbox and the
notification center.

`deploy-oci.yml` builds an immutable `amd64`/`arm64` image, publishes it to
GHCR and deploys it to an OCI VM. The VM must already contain Docker, a GHCR
login for private images and an `.env.production` file in `OCI_APP_PATH`.

Configure the GitHub `production` environment with:

- `OCI_HOST`
- `OCI_USER`
- `OCI_SSH_KEY`
- `OCI_APP_PATH`

Database and storage credentials stay in `.env.production` on the server and
are never copied into the image.
