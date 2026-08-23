# FlowTXT

![Java](https://img.shields.io/badge/Java-21-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Spring Boot](https://img.shields.io/badge/Spring_Boot-4.1-6DB33F?style=for-the-badge&logo=spring&logoColor=white)
![Maven](https://img.shields.io/badge/Maven-3.9+-C71A36?style=for-the-badge&logo=apache-maven&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7-DC382D?style=for-the-badge&logo=redis&logoColor=white)
![JWT](https://img.shields.io/badge/JWT-000000?style=for-the-badge&logo=json-web-tokens&logoColor=white)
![CI](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white)

FlowTXT is an **SMS delivery backend** built with **Java 21**, **Spring Boot 4.1** and a strict
**Clean Architecture** (multi-module: domain / application / infrastructure / api). It manages
contacts, sends SMS through **Twilio** (with a fake adapter for dev/test), tracks delivery
status in **PostgreSQL** (schema owned by Flyway), uses **Redis** for caching, and secures every endpoint with **JWT**
authentication.

**Project docs:** [AGENTS.md](AGENTS.md) (rules for solo/AI-assisted development) ·
[docs/coding-standards.md](docs/coding-standards.md) (coding standards) ·
[docs/testing-playbook.md](docs/testing-playbook.md) (testing guide) ·
[docs/twelve-factor.md](docs/twelve-factor.md) (12-factor compliance) ·
[docs/lessons.md](docs/lessons.md) (engineering lessons) · [CHANGELOG.md](CHANGELOG.md).

## Table of Contents

- [Tech Stack](#tech-stack)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Commands](#commands)
- [Authentication](#authentication)
- [API & Documentation](#api--documentation)
- [Testing](#testing)
- [Security](#security)
- [Releases & Rollout](#releases--rollout)
- [Current State](#current-state)
- [Roadmap](#roadmap)

## Tech Stack

| Category | Technology |
| :--- | :--- |
| **Language & Runtime** | Java 21 (Temurin), Spring Boot 4.1 (Tomcat 11, virtual threads) |
| **Build** | Maven 3.9 (with `./mvnw` wrapper), multi-module reactor |
| **Persistence** | PostgreSQL 16 (Spring Data JPA + Flyway) |
| **Cache** | Redis 7 (Spring Data Redis) |
| **SMS** | Twilio SDK 9 (`TwilioSmsAdapter` in `prod`, `FakeSmsAdapter` in `dev`/`test`) |
| **Auth** | Spring Security 7 + JJWT 0.12 (stateless bearer tokens) |
| **API docs** | springdoc-openapi (Swagger UI) |
| **CI / Deploy** | GitHub Actions (unit tests → quality gates → `*IT` → image with Trivy + SBOM) |
| **Testing** | JUnit 5, Mockito, Testcontainers (PostgreSQL + Redis) |

## Architecture

Clean Architecture with a strict dependency rule that always points inward:

```
flowtxt-domain/         Entities, value objects & outbound port interfaces (Contact, Message,
│                       User, PhoneNumber, MessageStatus, Role, PasswordHasher) — zero framework
flowtxt-application/    Use-case orchestration (ports in/out) — pure Java
│                       RegisterContact, SendMessage, UpdateMessageStatus, RegisterUser, AuthenticateUser
flowtxt-infrastructure/ Adapters: JPA repositories + mappers, Redis cache, Twilio/fake SMS,
│                       JWT (service/filter/UserDetails/hasher), SecurityConfig, UseCaseConfig
flowtxt-api/            Spring Boot app + thin REST controllers + DTOs + GlobalExceptionHandler
```

**Boundary rules:** `domain`/`application` never import `infrastructure` or frameworks; every
external concern is behind a port implemented by an adapter; controllers only call
`application/port/in` interfaces.

## Requirements

- JDK 21
- Maven 3.9+ (or use the bundled `./mvnw`)
- Docker and Docker Compose (for PostgreSQL + Redis, and for the integration tests)

## Getting Started

### 1. Start the external services

```sh
docker compose -f docker/docker-compose.yaml up -d   # PostgreSQL + Redis
```

### 2. Configure environment

```sh
cp .env.example .env   # fill TWILIO_* and JWT_SECRET
```

### 3. Run the application

```sh
./mvnw spring-boot:run -pl flowtxt-api
```

The API is available at http://localhost:8080, Swagger UI at
http://localhost:8080/swagger-ui.html.

## Commands

| Purpose | Command |
| :--- | :--- |
| Run the dev server | `./mvnw spring-boot:run -pl flowtxt-api` |
| Unit tests (no Docker) | `./mvnw test` |
| Integration tests (Docker) | `./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false` |
| Coverage report / check | `./mvnw jacoco:report` / `./mvnw jacoco:check` |
| Static analysis | `./mvnw spotbugs:check` |
| Dependency check | `./mvnw dependency-check:check -DfailBuildOnAnyVulnerability=false` |
| Production build | `./mvnw clean package` → `flowtxt-api/target/flowtxt-api-1.0-SNAPSHOT.jar` |
| Seed demo dev data | `./scripts/seed-dev-data.sh` (idempotent, API-based) |
| Database shell | `./scripts/psql.sh` |
| Smoke test | `./scripts/smoke-test.sh` (boots the whole stack) |

## Authentication

All endpoints except `/auth/register` and `/auth/login` require a bearer token.

```sh
# register
curl -X POST http://localhost:8080/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"strongpass123"}'
# → 201 {"token":"<jwt>","email":"user@example.com","role":"USER"}

# login
curl -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"strongpass123"}'
# → 200 {"token":"<jwt>", ...}
# beyond the per-client rate limit → 429 + Retry-After header

# use the token
curl -X POST http://localhost:8080/contacts \
  -H "Authorization: Bearer <jwt>" \
  -H "Content-Type: application/json" \
  -d '{"name":"Maria","phoneNumber":"+5511999999999"}'
```

## API & Documentation

Interactive docs (Swagger UI): http://localhost:8080/swagger-ui.html.

| Endpoint | Method | Auth | Description |
| :--- | :--- | :--- | :--- |
| `/auth/register` | `POST` | public | Register a user, returns a JWT. |
| `/auth/login` | `POST` | public | Authenticate, returns a JWT. Rate-limited per client (429 + `Retry-After` beyond the limit). |
| `/contacts` | `POST` | JWT | Register a contact. |
| `/messages` | `POST` | JWT | Send an SMS to a contact. |
| `/webhook/twilio/status` | `POST` | see debt¹ | Receives Twilio delivery-status callbacks and updates message status. |

> ¹ Public at the HTTP-security layer and protected by Twilio request-signature validation
> (`X-Twilio-Signature`, HMAC-SHA1 with the account auth token); invalid or unsigned requests
> are rejected with 403. Behind a proxy, the app must see the same public URL Twilio dialed.

## Testing

Pyramid of **75 unit tests** (domain → application → infrastructure → API slice) plus
**7 integration tests** (`*IT`, Testcontainers with real PostgreSQL + Redis) covering repository
adapters, the cache, login rate limiting and the end-to-end security flow. Full guidance:
[docs/testing-playbook.md](docs/testing-playbook.md).

## Security

- **JWT authentication** (see [docs/adr/0001-jwt-authentication.md](docs/adr/0001-jwt-authentication.md)) —
  stateless bearer tokens, BCrypt password hashing behind the `PasswordHasher` port.
- `SecurityConfig` is the single source of truth for route authorization; new endpoints must
  declare an explicit rule (AGENTS.md rule 7).
- Secrets (Twilio, `JWT_SECRET`) come from the environment; the `jwt.secret` in
  `application.yaml` is a dev-only placeholder that production must override.
- CI gates: SpotBugs, OWASP Dependency Check, Trivy (HIGH/CRITICAL) on the container image,
  CodeQL, Dependency Review.

## Releases & Rollout

One pipeline, three artifact tiers (all built by the same CI run, so a commit
always maps to the same jar and image):

| Trigger | Artifacts | Where |
| :--- | :--- | :--- |
| Push to `main` | Image `ghcr.io/daniel-castilho/flowtxt-api:sha-<short7>` (immutable) + `:edge` (moving) | GHCR |
| Annotated tag `vX.Y.Z` | Image `ghcr.io/daniel-castilho/flowtxt-api:X.Y.Z` + GitHub Release with `flowtxt-api-X.Y.Z.jar` and SBOM | GHCR + GitHub Releases |

**Cutting a release** (milestone with the Definition of Done met — coding
standards §9):

```sh
git checkout main && git pull
git tag -a v1.0.0 -m "Release 1.0.0" && git push origin v1.0.0
```

CI runs every gate on the tagged commit, publishes the semver image tag,
and opens the GitHub Release with auto-generated notes plus the jar and the
CycloneDX SBOM of the exact shipped image.

**Rolling out**: deploy by pinning an immutable tag — never a moving one:

```sh
docker run -d --restart unless-stopped \
  --env-file .env \
  -p 8080:8080 \
  ghcr.io/daniel-castilho/flowtxt-api:1.0.0
```

Rollback = re-run against the previous immutable tag. The Maven version stays
`1.0-SNAPSHOT` in development; release naming comes from git tags.

## Current State

- JWT auth (register/login + protected routes; missing tokens get a proper 401), user
  persistence in PostgreSQL.
- **Rich immutable domain model**: entities with behaviour (`Message` guards its forward-only
  status lifecycle; invalid transitions map to HTTP 409), factories instead of builders,
  equality by identity, and value objects that validate themselves (`PhoneNumber` enforces
  strict ITU-T E.164). No setters anywhere in the domain.
- Contact + message flow with PostgreSQL persistence and Twilio/fake SMS adapters; provider
  failures now transition the message to `FAILED`.
- **Fail-fast configuration validation**: the boot aborts with one aggregated report when
  required config is missing/invalid (unresolved placeholders, short JWT secrets, missing Twilio
  credentials outside dev). Production must run with `SPRING_PROFILES_ACTIVE=prod` so the strict
  rules apply.
- **Login rate limiting**: `/auth/login` throttled by a Redis-backed fixed window per client
  (first `X-Forwarded-For` hop, else remote address); beyond `rate-limit.limit` requests get
  `429` + `Retry-After`. Atomic Lua script (no orphan keys), shared across replicas, fails open
  (with a WARN log) if Redis is unavailable. Configurable via `RATE_LIMIT_*` env vars.
- Twilio delivery-status webhook (`POST /webhook/twilio/status`) wired through
  `UpdateMessageStatusUseCase`; unknown statuses map to `UNKNOWN`. Route authorization for
  Twilio callbacks still pending (see AGENTS debt).
- Quality gates green locally: unit tests, SpotBugs (all modules), JaCoCo ≥ 0.40 per module
  (actual: domain 94.6%, application 88.2%, infrastructure 52.5%, api 45.5%), full CI/CD and
  governance docs.
- 60 unit tests + 6 integration tests; Maven wrapper; Dockerfile (non-root); Redis in compose.
- Sources are 100% English (identifiers, comments, logs); legacy Portuguese comments removed.

## Roadmap

Deliberately not implemented yet (candidate backlog — see `tasks/`):

- Raise the JaCoCo coverage target further (0.40 → 0.50+) as the suite grows.
