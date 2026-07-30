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
through workflows with changes persisted in PostgreSQL.

## Technology

- Lucee 6 and ColdBox 7
- cbI18n resource bundles for English and Brazilian Portuguese
- PostgreSQL 17
- MinIO for local attachment storage
- Docker Compose for the complete development environment
- GitHub Actions for CI and multi-platform OCI deployment
- Flyway migrations for local and managed PostgreSQL
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

## Delivery

`ci.yml` validates translations, builds the application, starts the complete
stack and checks application, PostgreSQL and MinIO health. Its functional smoke
test also covers account lifecycle, cards, attachments, members, boards, lanes,
plan limits, archiving and WIP enforcement.

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
