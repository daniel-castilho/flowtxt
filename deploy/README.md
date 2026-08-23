# FlowTXT — Deployment

Production-shaped local/staging stack and deploy/rollback scripts. The
operational runbook lives in
[`../docs/release-runbook.md`](../docs/release-runbook.md).

## Files

| File | Purpose |
| :--- | :--- |
| `docker-compose.prod.yml` | Self-contained stack: hardened `app` (non-root, read-only root FS, tmpfs `/tmp`, resource limits, health check) plus PostgreSQL 16 and Redis 7 for local/staging use. |
| `.env.example` | The operator contract: every env var the `prod` profile requires. Copy to `.env` (gitignored) and fill in. |

Scripts in the repo root `scripts/`:

| Script | Purpose |
| :--- | :--- |
| `scripts/deploy.sh <immutable-tag>` | Pull the pinned image, recreate `app`, health-gate on `/actuator/health/readiness`; on failure automatically roll back to the previous tag. |
| `scripts/rollback.sh <immutable-tag>` | Recreate `app` at the previous tag and wait for readiness. |
| `scripts/shutdown-under-load-test.sh [jar] [port] [concurrency]` | Reproducible graceful-shutdown-under-load verification (in-flight requests complete, readiness drops, exit within the 30s grace period). |

## First deploy (local/staging)

```sh
cp deploy/.env.example deploy/.env
# edit deploy/.env: set JWT_SECRET (openssl rand -base64 48), DB_PASSWORD, Twilio values, IMAGE_TAG
docker compose -f deploy/docker-compose.prod.yml up -d
./scripts/deploy.sh "$IMAGE_TAG"
curl -fsS http://localhost:8080/actuator/health/readiness   # 200
```

On a fresh volume the app may report unhealthy until PostgreSQL is ready; the
`depends_on` health conditions order startup, and the container restarts with
`unless-stopped`.

## Runtime contract

| Concern | Setting |
| :--- | :--- |
| Profile/secrets | `SPRING_PROFILES_ACTIVE=prod`; all values from `deploy/.env` (gitignored). `JWT_SECRET` never in Git/images. |
| Non-root | Image runs UID/GID 10001 (verified in CI); compose adds `read_only: true` + tmpfs `/tmp`, `cap_drop: ALL`, `no-new-privileges`. |
| Resource limits | App 1.5 CPU / 768 MB; Postgres 1 CPU / 512 MB; Redis 0.5 CPU / 128 MB. |
| Probes | Container healthcheck on `/actuator/health/readiness`; liveness/readiness are the only public actuator paths. |
| Graceful shutdown | `server.shutdown=graceful` + 30s `timeout-per-shutdown-phase`; `deploy.sh`/`rollback.sh` wait for readiness. |
| Restart policy | `unless-stopped` on every service. |
| Immutable artefact | `IMAGE_TAG` references an immutable `sha-<short7>` or semver tag built by CI; never `edge`/`latest`. |

## Deploy / rollback

```sh
# health-gated cutover (fails back to the previous tag automatically)
./scripts/deploy.sh ghcr.io/daniel-castilho/flowtxt-api:sha-abcdef0

# instant rollback
./scripts/rollback.sh ghcr.io/daniel-castilho/flowtxt-api:sha-previous
```

`deploy.sh` records the newly deployed tag back into `deploy/.env` as
`IMAGE_TAG` so the next rollback knows the previous value.

## Notes for a managed production environment

When PostgreSQL/Redis are managed services rather than the bundled compose
services, deploy only the `app` container (or the platform equivalent), point
`DATABASE_URL`/`REDIS_HOST` at the managed endpoints, and let the platform's
health check poll `/actuator/health/readiness`. The app is stateless and
scales horizontally behind any HTTP load balancer; the login rate limiter is
backed by Redis and shared across replicas.
