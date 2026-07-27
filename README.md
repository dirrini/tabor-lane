# Tabor Lane

Tabor Lane is a modular Kanban workspace for clear, connected work. This
repository contains the first product foundation: a bilingual server-rendered
landing page, application preview, PostgreSQL schema and local S3-compatible
attachment storage.

The application now includes functional account registration and login. Every
new account creates a Free workspace, links the user as its owner and provisions
an initial board. Authenticated users can create cards and move them between
columns with changes persisted in PostgreSQL.

## Technology

- Lucee 6 and ColdBox 7
- cbI18n resource bundles for English and Brazilian Portuguese
- PostgreSQL 17
- MinIO for local attachment storage
- Docker Compose for the complete development environment
- GitHub Actions for CI and multi-platform OCI deployment

## Run locally

Requirements: Docker Desktop with Docker Compose.

```powershell
Copy-Item .env.example .env
docker compose up --build --wait
```

Open:

- Product: <http://localhost:8090>
- Workspace preview: <http://localhost:8090/app>
- MinIO Console: <http://localhost:9001>
- Readiness: <http://localhost:8090/health/ready>

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

## Delivery

`ci.yml` validates translations, builds the application, starts the complete
stack and checks application, PostgreSQL and MinIO health. Its functional smoke
test also creates an account, verifies workspace ownership and persists a card.

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
