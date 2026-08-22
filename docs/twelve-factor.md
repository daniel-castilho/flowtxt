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
| 5 | Build, release, run | ⚠️ Partial | Build = `./mvnw clean package`; run = `java -jar flowtxt-api/target/*.jar`. CI (`.github/workflows/ci.yml`) runs tests, quality gates and image build (non-root, Trivy, SBOM). **TBD:** explicit release tagging/rollout. |
| 6 | Processes | ✅ Stateless | JWT stateless auth; no in-memory session state across requests. Cross-process state (cache, login rate limiting) lives in Redis. |
| 7 | Port binding | ✅ Self-contained | App exposes HTTP on `server.port` (8080) via Spring Boot; no external web server injected. |
| 8 | Concurrency | ✅ Process-based | Scales by spawning processes; each is a copy of the same stateless app. |
| 9 | Disposability | ✅ Fast boot/shutdown | Spring Boot boots quickly; graceful shutdown on SIGTERM. |
| 10 | Dev/prod parity | ✅ Containers | `docker compose` (PostgreSQL + Redis) keeps local close to prod. |
| 11 | Logs | ✅ Mostly | Output goes to stdout (Spring Boot + `console`). No app writes log files. Never log secrets (Twilio token masked). |
| 12 | Admin processes | ⚠️ Partial | One-off tasks run as separate commands (e.g. DB seeding) — **TBD:** a `scripts/` convention for release-time admin steps. |

Legend: ✅ compliant · ⚠️ partially compliant / has an open TODO.

## Hard rules to keep the list green

- Never hardcode environment-specific values (URLs, secrets, credentials) in code. Read them
  from env vars, with dev-only defaults in `.env.example`.
- Secrets live only in env vars / the deployed environment — never in git, code, or logs.
- Every build must be reproducible: `./mvnw clean package` from a clean checkout.
- Local dev must match production dependencies as closely as possible (`docker compose`).

## Open TODOs (tracked)

1. Release tagging/rollout convention (image + jar versioned per commit).
2. `scripts/` for admin/one-off operations (e.g. seed data).
