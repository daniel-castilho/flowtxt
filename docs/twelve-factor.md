# Twelve-Factor App — Reference & Compliance (FlowTXT)

The project follows the [Twelve-Factor App](https://12factor.net/) methodology. Goal: a codebase
that deploys identically to any environment with no code changes, reproducible builds, and easy
horizontal scaling.

> **This is a commitment, not a suggestion.** When writing or reviewing code, check the factor
> affected by the change and keep the table below green.

## The 12 factors and how FlowTXT complies

| # | Factor | FlowTXT status | Notes |
| - | ------- | -------------- | ----- |
| 1 | Codebase | ✅ One repo, one app | Git repo `daniel-castilho/flowtxt`, `main` branch. Multi-module Maven reactor (one deployable artifact: `flowtxt-api`). |
| 2 | Dependencies | ✅ Declared & locked | `pom.xml` per module + Maven wrapper (`./mvnw`). Reproducible via `./mvnw clean package`. |
| 3 | Config | ✅ Compliant | Environment-specific values live in env vars (`.env`, see `.env.example`): Twilio credentials and `JWT_SECRET`. `StartupConfigValidator` fails the boot with an aggregated report when required config is missing/invalid — and outside dev it rejects the dev placeholder secret and missing Twilio credentials outright. |
| 4 | Backing services | ✅ Attached resources | PostgreSQL + Redis are external resources addressed by URI/env (`docker/docker-compose.yaml`). No embedded servers. |
| 5 | Build, release, run | ✅ Compliant | Build = `./mvnw clean package`; run = `java -jar flowtxt-api/target/*.jar`. CI (`.github/workflows/ci.yml`) runs tests, quality gates and image build (non-root, Trivy, SBOM). Every `main` push publishes an immutable `sha-<short>` image tag (+ moving `edge`) to GHCR; annotated `v*` tags publish semver image tags and a GitHub Release with the versioned jar + SBOM. Rollout = pin an immutable tag (see README "Releases & Rollout"). |
| 6 | Processes | ✅ Stateless | JWT stateless auth; no in-memory session state across requests. Cross-process state (cache, login rate limiting) lives in Redis. |
| 7 | Port binding | ✅ Self-contained | App exposes HTTP on `server.port` (8080) via Spring Boot; no external web server injected. |
| 8 | Concurrency | ✅ Process-based | Scales by spawning processes; each is a copy of the same stateless app. |
| 9 | Disposability | ✅ Fast boot/graceful shutdown | `server.shutdown=graceful` with a 30s `timeout-per-shutdown-phase` drains in-flight requests on SIGTERM; liveness/readiness probes gate the load balancer. |
| 10 | Dev/prod parity | ✅ Containers | `docker compose` (PostgreSQL + Redis) keeps local close to prod; the same jar and image run in all environments. |
| 11 | Logs | ✅ Compliant | Logs are event streams to stdout. The `prod` profile emits structured JSON via Spring Boot 4's built-in ECS formatter (one object per line, root-cause first, shortened stack traces) with no extra dependency. No app writes log files. Never log secrets (Twilio token masked). |
| 12 | Admin processes | ✅ Compliant | One-off tasks run as separate processes from `scripts/` (seed data, psql shell, smoke test, deploy/rollback, shutdown-under-load) against the same codebase, env-var config and backing services. Flyway owns schema changes. |

Legend: ✅ compliant · ⚠️ partially compliant / has an open TODO.

## Hard rules to keep the list green

- Never hardcode environment-specific values (URLs, secrets, credentials) in code. Read them
  from env vars, with dev-only defaults in `.env.example`.
- Secrets live only in env vars / the deployed environment — never in git, code, or logs.
- Every build must be reproducible: `./mvnw clean package` from a clean checkout.
- Local dev must match production dependencies as closely as possible (`docker compose`).

## Open TODOs (tracked)

None currently.
