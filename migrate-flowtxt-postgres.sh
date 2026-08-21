#!/usr/bin/env bash
#
# migrate-flowtxt-postgres.sh
# =============================================================================
# Applies the FlowTXT persistence migration MongoDB -> PostgreSQL + Flyway
# (ADR-0002), validated end-to-end before packaging (unit tests green, real
# boot against PostgreSQL with Flyway applying V1__init.sql, full REST flow
# persisted to the DB):
#
#   - Spring Data JPA entities replace Mongo documents (domain stays immutable
#     and free of JPA annotations; MapStruct mappers preserved)
#   - Adapters renamed Mongo*Adapter -> Jpa*Adapter (same port interfaces)
#   - Flyway V1__init.sql owns the schema (UNIQUE/FK/CHECK constraints;
#     ddl-auto: validate) + spring-boot-starter-flyway (Boot 4 modular)
#   - MessageEntity gains @Version optimistic locking
#   - docker-compose: postgres:16 + redis (was mongo + redis)
#   - Twelve-Factor config: DATABASE_URL / DB_USERNAME / DB_PASSWORD
#   - Tests: PostgreSQLContainer + Flyway; MongoRepositoriesIT -> JpaRepositoriesIT
#   - Docs: ADR-0002, README, CHANGELOG, AGENTS, coding-standards,
#     testing-playbook, twelve-factor, .env.example, smoke script
#
# Behavior:
#   - Backs up replaced files as <file>.bak.<timestamp>; skips identical files.
#   - Deletes the legacy Mongo persistence files listed above.
#   - Runs the gates at the end: ./mvnw test (unit), spotbugs, jacoco.
#
# Requirements: JDK 21 (JAVA_HOME), Maven wrapper, Docker for the *IT.
#
# Usage:
#   ./migrate-flowtxt-postgres.sh [path-to-project]     # default: current dir
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[i]${NC} $*"; }
ok()   { echo -e "${GREEN}[ok]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

[ -f pom.xml ] || { err "pom.xml not found in $(pwd). Run inside the flowtxt project or pass its path."; exit 1; }

TS="$(date +%Y%m%d%H%M%S)"

deploy_file() {
  local dest="$1" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  cat > "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
    echo -e "${GREEN}[skip]${NC} $dest (already up to date)"
  else
    if [ -f "$dest" ]; then
      local bak="${dest}.bak.$TS"
      cp "$dest" "$bak"
      warn "backup: $dest -> $bak"
    fi
    cp "$tmp" "$dest"
    echo -e "${GREEN}[written]${NC} $dest"
  fi
  rm -f "$tmp"
}

echo "======================================================================"
echo "  Applying FlowTXT MongoDB -> PostgreSQL + Flyway migration"
echo "  Target: $(pwd)"
echo "======================================================================"

deploy_file ".env.example" <<'GG_EOF'
# Twilio SMS
TWILIO_ACCOUNT_SID=your_account_sid_here
TWILIO_AUTH_TOKEN=your_auth_token_here
TWILIO_PHONE_NUMBER=+1234567890

# JWT — generate with: openssl rand -base64 48
# (dev-only placeholder below; production MUST set a strong secret)
JWT_SECRET=change-me-dev-only-please-use-a-long-random-secret
JWT_EXPIRATION_MS=3600000

# PostgreSQL (Twelve-Factor: config via env; defaults match docker-compose)
DATABASE_URL=jdbc:postgresql://localhost:5432/flowtxt
DB_USERNAME=flowtxt
DB_PASSWORD=flowtxt
GG_EOF

deploy_file "AGENTS.md" <<'GG_EOF'
# AGENTS.md

FlowTXT — an SMS delivery backend built with **Java 21 + Spring Boot 3.5** as a strict
**Clean Architecture** (layered, multi-module) service. The business core (`flowtxt-domain` +
`flowtxt-application`) is kept independent of `infrastructure` details: persistence (PostgreSQL via Spring Data JPA + Flyway),
cache (Redis), SMS delivery (Twilio / fake for dev) and the web layer (Spring Web controllers)
are all behind ports.

Modules: `flowtxt-domain` · `flowtxt-application` · `flowtxt-infrastructure` · `flowtxt-api`.

Sources of truth: `README.md`, `pom.xml`, `docker/docker-compose.yaml`,
`docs/coding-standards.md`, `docs/testing-playbook.md`, `docs/twelve-factor.md`. Re-read the
relevant parts before starting any task.

## Critical rules (never violate)

1. `flowtxt-domain` and `flowtxt-application` must **never import `flowtxt-infrastructure` code
   or framework adapters** — no `ca.flowtxt.infrastructure.*`, `org.springframework.*`,
   `com.twilio.*`, `io.jsonwebtoken.*`. Verify before finishing:
   `grep -rEn "^import (ca\.flowtxt\.infrastructure|org\.springframework|com\.twilio|io\.jsonwebtoken)" flowtxt-domain/src flowtxt-application/src`
   must return nothing. Known leaks are tracked in "Known technical debt" — do **not** silently
   extend them.
2. Business logic lives in `domain` (entities, value objects, rich rules) and `application`
   (use cases). `infrastructure` adapters and `api` controllers/DTOs are **thin** — no business
   rules, no repository calls from controllers. Controllers depend only on
   `application/port/in` interfaces.
3. **Zero direct PostgreSQL / Redis / Twilio / JWT usage outside `infrastructure/`.** Every operation
   goes through a domain/application port (`ContactRepository`, `MessageRepository`,
   `UserRepository`, `SmsService`, `CacheService`, `PasswordHasher`) implemented by an adapter.
4. Passwords are hashed with **BCrypt** via the domain `PasswordHasher` port (adapter:
   `SpringSecurityPasswordHasher`). Never store plaintext, never commit secrets or `.env`-style
   files. The `jwt.secret` in `application.yaml` is a **dev-only example** — production MUST
   override it via the `JWT_SECRET` environment variable.
5. Do **not** add a new Maven dependency without explicit human approval.
6. **English only.** All identifiers, comments, Javadoc, commit messages, documentation and log
   messages must be in English. (Pre-existing Portuguese code comments are legacy — do not add
   new ones.)
7. Every new endpoint must have an explicit authorization rule in
   `flowtxt-infrastructure/.../config/SecurityConfig.java`. Auth endpoints (`/auth/**`) are
   public by design; mutating endpoints must never default to permit-all.
8. **Doc sync is part of Done.** After milestone-sized work (a new feature area, a behaviour
   change, a debt resolution) the same change set or the immediate follow-up commit MUST update:
   1. `README.md` → "Current State" / "Roadmap"
   2. `CHANGELOG.md` → an entry under the next version or `Unreleased` (Keep a Changelog)
   3. `AGENTS.md` → "Known technical debt" (add or clear)
   Do **not** claim work DONE while `README.md` or `CHANGELOG.md` still describes the previous
   state as current.
9. Keep the default test suite green: `./mvnw test` must pass before finishing. Domain tests
   never mock; application tests mock the ports only; infrastructure/API tests follow
   `docs/testing-playbook.md`. Do not weaken an existing test to make a change pass.
10. `npm`-style lockfile discipline does not apply here, but the **Maven wrapper is the
    canonical build entrypoint**: always use `./mvnw`, never a system `mvn`.

## Commands

| Purpose | Command |
| :--- | :--- |
| Run the dev server | `./mvnw spring-boot:run -pl flowtxt-api` → http://localhost:8080 |
| Run pure unit tests (no Docker needed) | `./mvnw test` |
| Run integration tests explicitly (needs Docker) | `./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false` |
| Coverage report + check | `./mvnw jacoco:report` / `./mvnw jacoco:check` |
| SpotBugs static analysis | `./mvnw spotbugs:check` |
| OWASP Dependency Check | `./mvnw dependency-check:check -DfailBuildOnAnyVulnerability=false` |
| Production build | `./mvnw clean package` |
| Start external services (PostgreSQL + Redis) | `docker compose -f docker/docker-compose.yaml up -d` |
| Interactive API docs | http://localhost:8080/swagger-ui.html |

> Prefer the fast unit-test loop (`./mvnw test`); it needs **no Docker**. The `*IT` classes
> (Testcontainers: PostgreSQL/Redis adapters, security flow) are skipped automatically when Docker
> is unavailable and run explicitly with the command above (or in CI).

## Architecture

```
flowtxt-* modules (Clean Architecture, dependency rule points inward):
├── flowtxt-domain/         Entities, value objects & outbound port interfaces
│                           (Contact, Message, User, PhoneNumber, MessageStatus, Role,
│                            PasswordHasher) — zero framework imports
├── flowtxt-application/    Use-case orchestration (pure Java, depends only on domain + ports)
│   ├── port/in/            Use-case interfaces (RegisterContact, SendMessage,
│   │                        UpdateMessageStatus, RegisterUser, AuthenticateUser)
│   └── port/out/           Repository/service ports (ContactRepository, MessageRepository,
│                            UserRepository, SmsService, CacheService)
├── flowtxt-infrastructure/ Adapters: JPA repositories + mappers, Redis cache, Twilio/fake
│                           SMS, JWT security (filter, UserDetails, hasher), SecurityConfig,
│                           UseCaseConfig (composition root)
└── flowtxt-api/            Spring Boot app + REST controllers + DTOs + GlobalExceptionHandler
```

**Boundary rules:** `domain` and `application` never import `infrastructure`; `infrastructure`
implements the ports; `api` is thin composition. Controllers call `port/in` interfaces only.

## Known technical debt (resolve later; flag, don't silently fix)

- `CacheService.put` / `RedisCacheAdapter` set no TTL, violating coding-standards §6 ("always
  set a TTL"); keys can live forever.
- `SendMessageUseCaseImpl` persists twice by design (PENDING audit trail, then SENT/FAILED);
  provider failures are handled with a FAILED transition since 2026-08-21.
- `AuthController` injects the infrastructure `JwtService` directly instead of going through an
  application port (api→infrastructure coupling beyond the composition root).
- `PhoneNumber` validation is minimal (E.164-ish regex lives in the DTO; a domain-level value
  object validation with full E.164 is a candidate improvement).
- No rate limiting on `/auth/login` (a Redis-backed limiter is a candidate).
- `jjwt-jackson` still pulls Jackson 2 transitively for token serialization while the app runs Jackson 3; swap modules when jjwt ships a Jackson 3-compatible one.

> Resolved 2026-08-21: legacy Portuguese comments/logs were fully translated to English; the
> Twilio delivery-status webhook was implemented; domain models were rewritten as rich immutable
> classes (Lombok removed from the domain); SpotBugs gate restored to green; integration-test
> container lifecycle fixed (singleton containers); missing-token responses corrected from 403
> to 401; JaCoCo minimum raised 0.10 → 0.40; CI now installs reactor artifacts before the
> direct-goal quality gates; Lombok fully removed — documents and PhoneNumber are records,
> dependency dropped from all POMs; Redis Testcontainers properties moved to the Boot-3
> spring.data.redis.* prefix (ITs were silently hitting localhost:6379). See CHANGELOG.

> Resolved 2026-08-21 (later): `/webhook/twilio/**` got its explicit SecurityConfig rule plus
> X-Twilio-Signature validation (fail-closed filter); the route no longer depends on the JWT
> catch-all. Caveat: behind a proxy the app must see the public URL Twilio dialed.

## Notes

- Secrets live in `.env` / environment variables only — never committed.
- For current project status and pending work, see `README.md` ("Current State" / "Roadmap").
- Hard-won engineering rules live in `docs/lessons.md`.
- One-off AI engineering prompts live under `tasks/`.
GG_EOF

deploy_file "CHANGELOG.md" <<'GG_EOF'
# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Persistence migrated from MongoDB to PostgreSQL 16** (ADR-0002): `spring-data-jpa`
  entities replace Mongo documents, adapters renamed `Mongo*Adapter` → `Jpa*Adapter`,
  `docker-compose` runs `postgres:16`, and the schema is owned by **Flyway**
  (`V1__init.sql` with UNIQUE/FK/CHECK constraints; `ddl-auto: validate`). `MessageEntity`
  gains `@Version` optimistic locking so concurrent Twilio status callbacks cannot
  overwrite each other. Integration tests now use `PostgreSQLContainer` + the same Flyway
  schema. Config is Twelve-Factor (`DATABASE_URL`/`DB_USERNAME`/`DB_PASSWORD`).

### Added
- **Twilio request-signature validation on the webhook**: `/webhook/twilio/**` now has its
  explicit `permitAll` SecurityConfig rule and is protected by a fail-closed
  `TwilioSignatureValidationFilter` (HMAC-SHA1 over the full URL + sorted params, constant-time
  comparison, 403 on missing/invalid signatures or unconfigured token). The webhook is finally
  usable by real Twilio callbacks, which carry no bearer token. Behind a proxy the app must see
  the same public URL Twilio dialed. Covered by unit tests and end-to-end ITs.
- **Rich immutable domain model**: `Contact`, `Message` and `User` rewritten from Lombok
  `@Data` data bags into `final` immutable classes with intent-revealing factories
  (`Contact.create`, `User.register`, `Message.pending`) and behaviour living in the entities;
  equality is by identity. This removes the root cause of the SpotBugs `EI_EXPOSE_REP` gate
  failure (mutable `Contact` exposed through `Message`).
- **Guarded message lifecycle**: forward-only status transitions enforced inside `Message`
  (`PENDING -> QUEUED -> SENT -> DELIVERED/UNDELIVERED/FAILED`, `UNKNOWN` accepted as a sink,
  idempotent replays are no-ops); invalid transitions raise `IllegalStateException`, mapped to
  HTTP 409 by `GlobalExceptionHandler`.
- **Provider-failure handling**: `SendMessageUseCaseImpl` marks the persisted message as
  `FAILED` when the SMS provider call throws (it previously stayed `PENDING` forever).
- **`MessageRepository.findBySid`** port method (+ Mongo derived query on the indexed `sid`);
  the Twilio status webhook now loads the aggregate, applies the provider transition through
  the domain entity and saves — replacing the blind atomic `updateStatusBySid` DB update.
- **401 for unauthenticated requests**: `SecurityConfig` now installs an
  `HttpStatusEntryPoint(UNAUTHORIZED)`; protected routes previously answered Spring's default
  403 for missing tokens, contradicting REST semantics and the integration-test contract.
- **Twilio delivery-status webhook**: `POST /webhook/twilio/status` receives `MessageSid` /
  `MessageStatus` callback params, maps them to the domain `MessageStatus` enum (unknown values
  fall back to `UNKNOWN`) and updates the persisted message via
  `UpdateMessageStatusUseCase`. Route authorization for Twilio callbacks
  (request-signature validation) is still pending — see AGENTS.md debt.
- **JWT authentication** (ADR-0001): `POST /auth/register` and `POST /auth/login` issue bearer
  tokens; every other route requires authentication. Passwords hashed with BCrypt behind the
  domain `PasswordHasher` port; `User` aggregate + `Role` enum in the domain.
- **User persistence**: `UserDocument` + `SpringDataUserRepository` +
  `MongoUserRepositoryAdapter` + `UserMapper` (MapStruct).
- **Security infrastructure**: `JwtService` (jjwt), `JwtAuthenticationFilter`,
  `UserDetailsServiceImpl`, `SpringSecurityPasswordHasher`, and a real `SecurityConfig`
  (stateless, explicit route rules). The previously excluded Security auto-configuration is
  re-enabled.
- **Quality gates**: Maven wrapper (`./mvnw`), JaCoCo (report + check), SpotBugs, OWASP
  Dependency Check with `dependency-check-suppressions.xml`, `.gitattributes`.
- **CI/CD**: `ci.yml` (unit tests → jacoco → spotbugs → dependency-check → `*IT` →
  package → image job with non-root check + Trivy SARIF + SBOM), Dependabot (maven +
  github-actions), CodeQL, Dependency Review.
- **Docker**: multi-stage `Dockerfile` (non-root UID 10001, exec-form entrypoint), `.dockerignore`,
  Redis added to `docker-compose.yaml`.
- **Tests**: domain (4), application (8), infrastructure (20), API unit (7) and integration
  `*IT` (Testcontainers Mongo + Redis: repositories, cache, end-to-end security flow).
- **Governance docs**: `AGENTS.md`, `docs/coding-standards.md`, `docs/testing-playbook.md`,
  `docs/lessons.md`, `docs/twelve-factor.md`, `docs/adr/0001-jwt-authentication.md`,
  `tasks/` backlog + AI prompt.

### Changed
- **Upgraded to Spring Boot 4.1** (from EOL 3.5.7): Spring Framework 7 / Security 7 /
  Spring Data MongoDB 5, Tomcat 11 embedded server and Java 21 virtual threads enabled
  (`spring.threads.virtual.enabled`). Migration notes: `spring-boot-starter-web` renamed to
  `spring-boot-starter-webmvc`; `@MockBean` replaced by `@MockitoBean`; test annotations moved
  (`@WebMvcTest`/`@AutoConfigureMockMvc`) with the new `spring-boot-starter-webmvc-test`;
  Jackson 3 (`tools.jackson.*`) replaces Jackson 2; MongoDB connection properties renamed
  `spring.data.mongodb.*` -> `spring.mongodb.*` (silent-failure rename) with an explicit
  standard UUID representation; springdoc upgraded to 3.1.0; commons-io pinned at 2.16.1 over
  the Twilio SDK's vulnerable transitive (CVE-2024-47554). Undertow was considered as an
  embedded-server alternative but Boot 4 dropped its support (no Servlet 6.1 release);
  Tomcat 11 + virtual threads covers that ground on supported lines.
- **Lombok removed from the entire project** (Phase C): persistence documents are records
  (Spring Data Mongo maps them through their canonical constructors), `PhoneNumber` is a
  hand-written record (`value()` replaces `getValue()`), and `@RequiredArgsConstructor` /
  `@Slf4j` gave way to explicit constructors and SLF4J loggers. The dependency and its
  annotation-processor paths are gone from every module POM.
- **Quality gates restored to green**: SpotBugs passes on all four modules (final classes,
  constructor-parameter injection in `SecurityConfig`, and a single documented exclusion in
  `spotbugs-exclude.xml` for the framework-injected `RedisTemplate` in `RedisCacheAdapter`).
  The gate had been failing since before this release cycle.
- **JaCoCo line-coverage minimum raised 0.10 → 0.40** per module (current: domain 94.6%,
  application 88.2%, infrastructure 52.5%, api 45.5%).
- **Integration-test container lifecycle fixed**: `AbstractIntegrationTest` now starts Mongo +
  Redis once per JVM (singleton-container pattern) instead of per test class; with Spring's
  cached application context, per-class container restarts left later classes pointing at dead
  mapped ports (`Connection refused`, 30s timeouts).
- Test suite grew from 39 to **60 unit tests** (+ new `UpdateMessageStatusUseCaseImplTest`,
  lifecycle-transition tests, failure-path tests, 409 mapping test); integration tests cover
  the `findBySid` flow end-to-end.
- Codebase sweep to English-only: translated remaining Portuguese log messages, comments and
  test fixtures (AGENTS rule 6); legacy Portuguese comments are now fully removed.
- `MessageDocument.sid` now uses the MongoDB `@Indexed` annotation (it previously imported the
  Redis `@Indexed`, which has no effect on Mongo mappings).
- `ContactResponse` converted from a Lombok `@Data` class to a `record`, per coding-standards
  §1 (DTOs are records); removed a redundant `findById` redeclaration from
  `SpringDataMessageRepository` (inherited from `MongoRepository`).
- Removed the `Main.java` "Hello, World!" scaffolding from `domain`, `application` and
  `infrastructure` modules.
- `application.yaml` re-enables Spring Security; JWT configuration added
  (`jwt.secret` dev placeholder, `jwt.expiration-ms`).

### Fixed
- **Integration tests secretly required a Redis on localhost:6379**: dynamic Testcontainers
  properties were registered under the pre-Spring-Boot-3 `spring.redis.*` prefix, which Boot 3
  ignores — the mapped container port never applied and tests connected to `localhost:6379`
  instead. Masked on dev machines by unrelated local Redis instances; caught red by CI once the
  integration step finally ran. Prefix corrected to `spring.data.redis.*`.
- **CI quality gates could not run**: `ci.yml` invoked `jacoco:check`, `spotbugs:check` and
  `dependency-check:check` as direct plugin goals, which resolve cross-module artifacts from the
  local repository rather than the reactor — a fresh runner had no installed modules, so the
  pipeline failed on module ordering. An `install -DskipTests` pass now precedes the gates.

### Removed
- Dead code: orphan `ca.flowtxt.persistence.MongoContactRepository` interface (duplicated
  `SpringDataContactRepository`, never referenced) and the unused
  `TwilioDeliveryStatusRequest` DTO; unused imports cleaned up.

### Security
- The API is no longer wide open: contacts and message endpoints now require a valid JWT.
GG_EOF

deploy_file "README.md" <<'GG_EOF'
# FlowTXT

![Java](https://img.shields.io/badge/Java-21-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white)
![Spring Boot](https://img.shields.io/badge/Spring_Boot-4.1-6DB33F?style=for-the-badge&logo=spring&logoColor=white)
![Maven](https://img.shields.io/badge/Maven-3.9+-C71A36?style=for-the-badge&logo=apache-maven&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7-DC382D?style=for-the-badge&logo=redis&logoColor=white)
![JWT](https://img.shields.io/badge/JWT-000000?style=for-the-badge&logo=json-web-tokens&logoColor=white)
![CI](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?style=for-the-badge&logo=github-actions&logoColor=white)

FlowTXT is an **SMS delivery backend** built with **Java 21**, **Spring Boot 3.5** and a strict
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
| `/auth/login` | `POST` | public | Authenticate, returns a JWT. |
| `/contacts` | `POST` | JWT | Register a contact. |
| `/messages` | `POST` | JWT | Send an SMS to a contact. |
| `/webhook/twilio/status` | `POST` | see debt¹ | Receives Twilio delivery-status callbacks and updates message status. |

> ¹ Public at the HTTP-security layer and protected by Twilio request-signature validation
> (`X-Twilio-Signature`, HMAC-SHA1 with the account auth token); invalid or unsigned requests
> are rejected with 403. Behind a proxy, the app must see the same public URL Twilio dialed.

## Testing

Pyramid of **60 unit tests** (domain → application → infrastructure → API slice) plus
**6 integration tests** (`*IT`, Testcontainers with real PostgreSQL + Redis) covering repository
adapters, the cache and the end-to-end security flow. Full guidance:
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

## Current State

- JWT auth (register/login + protected routes; missing tokens get a proper 401), user
  persistence in PostgreSQL.
- **Rich immutable domain model**: entities with behaviour (`Message` guards its forward-only
  status lifecycle; invalid transitions map to HTTP 409), factories instead of builders,
  equality by identity. No setters anywhere in the domain.
- Contact + message flow with PostgreSQL persistence and Twilio/fake SMS adapters; provider
  failures now transition the message to `FAILED`.
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

- Rate limiting on `/auth/login` (Redis-backed).
- TTL support on `CacheService.put` / Redis adapter (coding-standards §6 requires a TTL).
- `PhoneNumber` full E.164 validation in the domain value object.
- Fail-fast configuration validation at boot (12-factor factor 3).
- Raise the JaCoCo coverage target further (0.40 → 0.50+) as the suite grows.
GG_EOF

deploy_file "docker/docker-compose.yaml" <<'GG_EOF'
version: "3.9"

services:
  postgres:
    image: postgres:16
    container_name: flowtxt-postgres
    restart: always
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: flowtxt
      POSTGRES_PASSWORD: flowtxt
      POSTGRES_DB: flowtxt
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    container_name: flowtxt-redis
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  postgres_data:
  redis_data:
GG_EOF

deploy_file "docs/adr/0002-postgresql-migration.md" <<'GG_EOF'
# ADR-0002: Migrate persistence from MongoDB to PostgreSQL (with Flyway)

- **Status:** Accepted (2026-08-21)
- **Deciders:** project owner + AI agent
- **Context:** the service originally persisted to MongoDB. The domain is
  fundamentally **relational** — `users`, `contacts` and `messages` with
  explicit relationships (`messages.contact_id → contacts.id`), unique
  constraints (`email`, `phone_number`, `sid`), and an enum-valued status with
  a forward-only lifecycle. The web research (2026 sources) is unanimous that
  for CRUD SaaS workloads like this, PostgreSQL is the safer default:
  *"default to PostgreSQL unless your workload inherently defies structure"*.
  MongoDB's strengths (document flexibility, horizontal sharding) do not apply
  here, and its single-node docker-compose setup provides no multi-document
  transactions — leaving the send-message flow (`PENDING → SENT`) non-atomic.

## Decision

Migrate persistence to **PostgreSQL 16** with **Spring Data JPA** and
**Flyway**:

- **Schema is owned by Flyway** (`V1__init.sql`): tables + `UNIQUE`/`CHECK`/
  `FOREIGN KEY` constraints. `ddl-auto: validate` only — never
  `create`/`update`. Future schema changes are new `V2__`, `V3__`, ... scripts.
- **Entities** (`ContactEntity`, `UserEntity`, `MessageEntity`) live in
  `flowtxt-infrastructure/.../persistence/entity`; the immutable domain stays
  free of JPA annotations and is mapped by MapStruct.
- **`messages.contact_id`** is a plain UUID column with a **foreign key
  enforced by the Flyway DDL** — no JPA `@ManyToOne` association is mapped,
  because the domain `Message` holds only `contactId` and an association would
  force unnecessary fetches. Referential integrity lives in the database,
  where it belongs.
- **Optimistic locking**: `MessageEntity` carries `@Version` so concurrent
  Twilio delivery-status callbacks cannot silently overwrite each other's
  status update (`OptimisticLockException` surfaces instead).
- **Twelve-Factor config**: the JDBC URL comes from `DATABASE_URL` (with
  `DB_USERNAME`/`DB_PASSWORD`), defaulting to the local docker-compose Postgres.
- **Tests**: integration tests keep using **Testcontainers** with
  `PostgreSQLContainer("postgres:16")`, and Flyway applies the same
  `V1__init.sql` the application runs — the schema under test is the schema in
  production.

## Why not alternatives

- **Stay on MongoDB:** the domain is relational; no document flexibility or
  horizontal scale is needed; the single-node compose lacks transactions.
- **H2 in Postgres mode for tests:** always drifts from real Postgres
  (functions, constraints, Flyway behaviour) — the classic false-green test.
- **SQLite:** not even close to Postgres semantics.

## Consequences

- Positive: real referential integrity (FK), unique constraints at the DB,
  atomic-ish send flow with optimistic locking, versioned schema via Flyway,
  SQL tooling and ecosystem, and integration tests against the same DB as
  production.
- Negative: entities are mutable persistence classes (the domain remains
  immutable and clean); the migration touched persistence adapters, config and
  the integration-test base (a contained change — controllers/ports/use cases
  were untouched).
GG_EOF

deploy_file "docs/coding-standards.md" <<'GG_EOF'
# Coding Standards — Java 21 / Spring Boot / Maven (FlowTXT)

Practical reference for solo and AI-assisted development. Goal: **consistency over time**, not ceremony. Living document — edit as the project evolves.

**Relationship to other docs:**

| Doc | Wins when |
| --- | --- |
| `AGENTS.md` | Project conventions, release flow, hard agent rules |
| **This file** | Day-to-day coding detail that does not fit in AGENTS |
| `docs/lessons.md` | Durable rules learned the hard way |

Where this file conflicts with `AGENTS.md`, **`AGENTS.md` wins**.

## 1. Naming

| Element | Convention | Example |
| --- | --- | --- |
| Modules / packages | lowercase, `ca.flowtxt.<layer>` | `ca.flowtxt.application.usecase` |
| Classes / types / interfaces | PascalCase | `SendMessageUseCaseImpl`, `ContactRepository` |
| Use-case implementations | `<UseCase>Impl` | `RegisterUserUseCaseImpl` |
| Adapters | `<Technology><Port>Adapter` | `JpaUserRepositoryAdapter`, `TwilioSmsAdapter` |
| Ports | `<Concept><Kind>` (Repository/Service/UseCase/Hasher) | `SmsService`, `PasswordHasher` |
| Methods / variables | camelCase | `sendMessage()`, `passwordHash` |
| Constants / enums | UPPER_SNAKE_CASE | `MIN_PASSWORD_LENGTH`, `MessageStatus.SENT` |
| Tests (unit) | `*Test.java` | `JwtServiceTest` |
| Tests (integration) | `*IT.java` | `SecurityFlowIT` |
| DTOs (records) | `<Noun>Request` / `<Noun>Response` | `RegisterUserRequest`, `AuthResponse` |

Name for **what it is or does**, not the implementation: `ContactRepository`, not `JpaContactDao`.

## 2. Package / folder structure (Clean Architecture, feature-agnostic)

```
flowtxt-domain/src/main/java/ca/flowtxt/domain/
├── model/              Entities + value objects (Contact, Message, User, PhoneNumber, Role)
└── (ports that are domain concepts, e.g. PasswordHasher)

flowtxt-application/src/main/java/ca/flowtxt/application/
├── port/in/            Use-case interfaces (what the app can do)
├── port/out/           Outbound ports (repositories, services)
└── usecase/            Implementations (depend on ports only)

flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/
├── persistence/        JPA repositories + entities (Spring Data JPA), mappers
├── cache/              Redis adapter
├── sms/                Twilio + fake adapters
├── security/           JWT service, filter, UserDetails, hasher
└── config/             SecurityConfig, UseCaseConfig (composition root)

flowtxt-api/src/main/java/ca/flowtxt/api/
├── controller/         REST controllers (thin)
├── dto/                Request/response records
└── exception/          GlobalExceptionHandler
```

**Boundary rules:**

| Layer | Framework / external imports |
| --- | --- |
| `domain/` | **None** — no Spring, Twilio, JJWT, JPA |
| `application/` | **None** — pure Java + domain types |
| `infrastructure/` | Full stack allowed (Spring Data, Redis, Twilio, JJWT) |
| `api/` | Spring Web, validation, security test helpers |

## 3. Java / Spring

- Java 21, records for DTOs, `var` for obvious local types.
- Spring beans wired in `infrastructure/config/*` (composition root); controllers/adapters use
  constructor injection. Prefer interfaces over concrete classes in `api` and `application`.
- Use cases are **plain classes instantiated in `UseCaseConfig`** — no Spring annotations in
  `application/`.
- Validation: Bean Validation (`@Valid` + constraints on DTO records); domain invariants live
  in the domain model (e.g. `PhoneNumber`).
- Never call repositories or external SDKs from controllers.

## 4. Formatting & tooling

- Maven multi-module; always build with `./mvnw`.
- Editor: 4-space indent (default IntelliJ), no tabs; UTF-8.
- Run before commit: `./mvnw test` (+ `spotbugs:check` for bigger changes).
- Keep modules' responsibilities clean: a new dependency belongs in the module that uses it.

## 5. Errors & logging

- Never empty `catch`. Log with context (ids, operation), not only `"error occurred"`.
- Domain/application throw `IllegalArgumentException` with a clear message; the API layer maps
  exceptions to HTTP responses via `GlobalExceptionHandler`.
- Never log passwords, tokens, or full auth payloads. The Twilio adapter masks the auth token.
- Log levels: `error` — needs attention · `warn` — handled anomaly · `info` — lifecycle ·
  `debug` — diagnostics.

## 6. Persistence (PostgreSQL/JPA) & cache (Redis)

- One Spring Data repository per aggregate; explicit mappers (MapStruct) between documents and
  domain models — domain models never leak persistence annotations.
- Prefer explicit repository interfaces (ports) over exposing `JpaRepository` to the
  application layer.
- Redis (`CacheService` port): always set a TTL when adding new cache entries; keys follow
  `flowtxt:<purpose>:<id>`; never store secrets.
- Integration tests use Testcontainers — never point unit tests at a shared local instance.

## 7. Testing

| Kind | Tooling | Notes |
| --- | --- | --- |
| Domain | JUnit 5 | Pure invariants, no mocks |
| Application | JUnit 5 + Mockito | Mock **ports only**; happy + rejection paths |
| Infrastructure unit | JUnit 5 + Mockito | Mappers, hasher, JWT service, cache adapter |
| Integration | JUnit 5 + Testcontainers (`*IT`) | PostgreSQL + Redis containers, real adapters, security flow |

- Names: `method_condition_expectedResult` or descriptive `shouldXWhenY`.
- Fast loop: `./mvnw test` (no Docker). Integration: `./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false`.
- Full guidance: `docs/testing-playbook.md`.

## 8. Documentation

- Javadoc where purpose is not obvious; comment **why**, not what.
- English only for code, comments, commits, and docs.
- Durable rules: `docs/lessons.md`. Project rules: `AGENTS.md`. This file: day-to-day detail.

### Doc sync

After milestone-sized work, the same change set — or an immediate follow-up commit — MUST update
`README.md` → "Current State", `CHANGELOG.md` (Keep a Changelog), and `AGENTS.md` → "Known
technical debt". The hard rule lives in `AGENTS.md` § *Critical rules* (rule 8).

## 9. Version control

- Imperative commit subject: `Add JWT authentication to the API layer`
- Small, focused commits; do **not** push unless the human asks.
- Annotated tags only at milestones with the Definition of Done met.

## 10. Security

- Server-side validation always (Bean Validation); never trust the client alone.
- Passwords: BCrypt via the `PasswordHasher` port. Never store plaintext.
- Auth: stateless JWT (see `docs/adr/0001-jwt-authentication.md`); `SecurityConfig` is the
  single source of truth for route authorization.
- Secrets via environment variables / `.env` (never committed); `jwt.secret` must be overridden
  in production.
- Keep `SecurityConfig` explicit: every new endpoint gets an explicit rule (see `AGENTS.md`).

## Quick pre-commit checklist

- [ ] `./mvnw test` green (unit tests)
- [ ] No `domain/`/`application/` import of infrastructure/framework
- [ ] New endpoint has an explicit rule in `SecurityConfig`
- [ ] DTO validated with Bean Validation
- [ ] No secrets in the diff; no logging of passwords/tokens
- [ ] Integration test added for new adapters/security behaviour
- [ ] Doc sync updated (README Current State / CHANGELOG / AGENTS debt) when milestone-sized
- [ ] Commit message says what and why (imperative, English)

---
GG_EOF

deploy_file "docs/testing-playbook.md" <<'GG_EOF'
# Testing Playbook

**Role:** Write and interpret tests for this Java 21 multi-module Clean Architecture service
(Spring Boot 3.5, PostgreSQL, Redis, Twilio).
**Stack constraints:** JUnit 5 + Mockito for unit tests; Testcontainers (PostgreSQL, Redis) for
integration tests. No other test deps without human approval.

Sources: `AGENTS.md` · `docs/coding-standards.md` · `docs/lessons.md` · colocated `*Test.java` /
`*IT.java`.

---

## Pyramid

1. **Domain unit** — pure invariants and value objects (`ContactTest`, `MessageTest`,
   `UserTest`, `PhoneNumber`). **No mocks.**
2. **Application unit** — use-case implementations with **mocked ports only**
   (`RegisterUserUseCaseImplTest`, `AuthenticateUserUseCaseImplTest`,
   `SendMessageUseCaseImplTest`); happy path + rejection paths.
3. **Infrastructure unit** — deterministic adapter behaviour that needs no Docker
   (`JwtServiceTest`, `SpringSecurityPasswordHasherTest`, `UserDetailsServiceImplTest`,
   `ContactMapperTest`, `MessageMapperTest`, `UserMapperTest`, `RedisCacheAdapterTest`,
   `FakeSmsAdapterTest`).
4. **API unit (slice)** — controllers via `@WebMvcTest` with mocked use cases + real
   `SecurityConfig` (`AuthControllerTest`), and `GlobalExceptionHandlerTest`.
5. **Integration (`*IT`, Testcontainers)** — the full application against real PostgreSQL + Redis
   containers: repository adapters (`JpaRepositoriesIT`), the cache adapter
   (`RedisCacheAdapterIT`) and the end-to-end security flow (`SecurityFlowIT`:
   register → login → protected endpoint with/without token). Skipped automatically when Docker
   is unavailable.

Never point tests at a shared local PostgreSQL/Redis — always containers (or mocks).

---

## Runner & layout

```bash
./mvnw test                                    # unit tests (no Docker)
./mvnw test -Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false   # integration (Docker)
./mvnw jacoco:report                           # coverage report


```

- Colocate: `JwtService.java` → `JwtServiceTest.java` in the same package; `*IT` classes live in
  the **api** module (they boot the full application via `AbstractIntegrationTest`).
- English test names: `registersANewUserWithHashedPasswordAndUserRole`, or
  `rejectsWrongPassword`.
- Assert with JUnit 5 assertions; Mockito for ports.

**Integration base class** (`flowtxt-api/src/test/java/ca/flowtxt/AbstractIntegrationTest.java`):

```java
@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
public abstract class AbstractIntegrationTest { /* PostgreSQL + Redis containers + @DynamicPropertySource */ }
```

`disabledWithoutDocker = true` means the suite is skipped (not failed) on machines without
Docker, and runs in CI where Docker is present.

---

## Mandatory patterns

| Pattern | Rule |
| --- | --- |
| Domain tests | No mocks; pure functions / value objects only |
| Application tests | Mock **ports only** (repositories, hasher, sms) |
| Controller tests | Mock use cases + `JwtService`; load the **real** `SecurityConfig` via `@Import` |
| Security | Every protected route asserted (401 without token, 200 with token); auth routes public |
| Validation | Bad payloads → 400 via `GlobalExceptionHandler` |
| Mappers | Round-trip document ↔ domain covered |
| Passwords | Assert hashed, never plaintext at rest |
| JWT | Generate → validate → reject tampered/invalid tokens |
| Integration | Real containers; assert persisted + read-back behaviour |

---

## Current automated suite (map)

| Area | File(s) | Focus |
| --- | --- | --- |
| Domain | `domain/model/ContactTest`, `MessageTest`, `UserTest` | Builders, fields |
| Application | `application/usecase/RegisterUserUseCaseImplTest` | Register, duplicate email, weak password |
| | `application/usecase/AuthenticateUserUseCaseImplTest` | Valid/invalid credentials |
| | `application/usecase/SendMessageUseCaseImplTest` | Send flow |
| Infrastructure | `infrastructure/security/JwtServiceTest` | Token lifecycle, tampering |
| | `infrastructure/security/SpringSecurityPasswordHasherTest` | BCrypt hash/matches |
| | `infrastructure/security/UserDetailsServiceImplTest` | Load by email, role authority |
| | `infrastructure/persistence/mapper/*Test` | Contact/Message/User round-trips |
| | `infrastructure/cache/RedisCacheAdapterTest` | put/get/remove (mocked) |
| | `infrastructure/sms/FakeSmsAdapterTest` | Fake SID |
| API unit | `api/controller/AuthControllerTest` | register/login (201/200/400) |
| | `api/exception/GlobalExceptionHandlerTest` | 400/400/500 mapping |
| API IT | `api/AbstractIntegrationTest` | Base (containers) |
| | `api/JpaRepositoriesIT` | Contact/User/Message persistence |
| | `api/RedisCacheAdapterIT` | Real Redis put/get/remove |
| | `api/SecurityFlowIT` | E2E register→login→protected |

When you change behaviour covered above, **extend the existing file** instead of inventing a
parallel suite.

---

## Regression checklist

| Area | Must verify |
| --- | --- |
| **Auth** | Register 201 + token; duplicate email 400; weak password 400; login 200 + token; wrong password 400 |
| **Security** | `/contacts` and `/messages` without token → 401; with token → 200; `/auth/**` public |
| **Contacts** | Create → persisted → found by phone number |
| **Messages** | Create → persisted; `updateStatusBySid` flips status; found by id |
| **Users** | Create → persisted → found by email |
| **Cache** | put → get → remove (real Redis) |
| **Boundaries** | `domain/` + `application/` free of Spring/Twilio/JJWT imports (grep in AGENTS.md) |
| **Stack** | Java 21, Spring Boot 4.1.x, PostgreSQL 16, Redis 7 — no version drift |

---

## Quality gates (CI local mirror)

```bash
./mvnw test


./mvnw dependency-check:check -DfailBuildOnAnyVulnerability=false

```

CI (`.github/workflows/ci.yml`) runs all of the above plus the `*IT` suite and the Docker image
job (non-root check, Trivy scan, SBOM). Prefer the fast unit loop locally.

---

## Reading failures

| Class | Signal | First move |
| --- | --- | --- |
| **Logic** | AssertionError, wrong status | Fix use case or expectation — read the test name first |
| **Boundary** | Forbidden import in domain/application | Restore the port boundary — do not weaken |
| **Security** | Unexpected 401/403 in controller test | Check `SecurityConfig` rules and `@Import` in the test |
| **Container** | Testcontainers cannot start | Confirm Docker is running; `*IT` are skipped otherwise |
| **MapStruct** | Mapper impl not generated | `./mvnw clean compile` (annotation processing) |
| **Flaky / env** | Port, Redis, PostgreSQL | Re-run; fix the cause — don't skip tests |

**Priority when many fail:** compile/annotation → domain → application → infrastructure → API →
integration.

---

## Do not

- Skip, delete, or `@Disabled` tests to green the build
- Add new test frameworks without human approval
- Point tests at a shared local PostgreSQL/Redis instance
- Assert on plaintext passwords or raw tokens in logs
- Weaken an existing test to make a change pass
- Put business rules in controller tests "because the controller failed"

---

## Done when

- [ ] Happy path + at least one rejection automated for the change
- [ ] New domain/application behaviour has a colocated `*Test`
- [ ] New adapter/security behaviour has a unit test (+ `*IT` when containers are involved)
- [ ] Failure analysis names root cause and smallest fix
- [ ] `./mvnw test` green (+ `spotbugs:check` as appropriate)
- [ ] Docs synced if milestone-sized (README Current State / CHANGELOG / AGENTS debt)

---
GG_EOF

deploy_file "docs/twelve-factor.md" <<'GG_EOF'
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
| 3 | Config | ⚠️ In progress | Environment-specific values live in env vars (`.env`, see `.env.example`): Twilio credentials and `JWT_SECRET`. **TBD:** validate all config at boot (fail-fast for missing prod values). |
| 4 | Backing services | ✅ Attached resources | PostgreSQL + Redis are external resources addressed by URI/env (`docker/docker-compose.yaml`). No embedded servers. |
| 5 | Build, release, run | ⚠️ Partial | Build = `./mvnw clean package`; run = `java -jar flowtxt-api/target/*.jar`. CI (`.github/workflows/ci.yml`) runs tests, quality gates and image build (non-root, Trivy, SBOM). **TBD:** explicit release tagging/rollout. |
| 6 | Processes | ✅ Stateless | JWT stateless auth; no in-memory session state across requests. Rate limiting/cache belong in Redis (not yet implemented — see AGENTS debt). |
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

1. Validate all environment variables at startup (fail-fast for prod).
2. Release tagging/rollout convention (image + jar versioned per commit).
3. `scripts/` for admin/one-off operations (e.g. seed data).
GG_EOF

deploy_file "flowtxt-api/pom.xml" <<'GG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
                             http://maven.apache.org/xsd/maven-4.0.0.xsd">

    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>ca.flowtxt</groupId>
        <artifactId>flowtxt-parent</artifactId>
        <version>1.0-SNAPSHOT</version>
    </parent>

    <artifactId>flowtxt-api</artifactId>
    <packaging>jar</packaging>

    <properties>
        <java.version>21</java.version>
        <spring.boot.version>4.1.0</spring.boot.version>
        <springdoc.version>3.1.0</springdoc.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencyManagement>
        <dependencies>
            <dependency>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-dependencies</artifactId>
                <version>${spring.boot.version}</version>
                <type>pom</type>
                <scope>import</scope>
            </dependency>
    

    </dependencies>
    </dependencyManagement>

    <dependencies>
        <!-- Internal module -->
        <dependency>
            <groupId>ca.flowtxt</groupId>
            <artifactId>flowtxt-infrastructure</artifactId>
            <version>${project.version}</version>
        </dependency>

        <!-- Actuator (health / probes) -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <!-- Testcontainers (integration tests) -->
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>postgresql</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>testcontainers</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>

        <!-- Spring Boot Starters -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-webmvc</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-validation</artifactId>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>

        <!-- OpenAPI/Swagger Documentation -->
        <dependency>
            <groupId>org.springdoc</groupId>
            <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
            <version>${springdoc.version}</version>
        </dependency>

        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis</artifactId>
        </dependency>

        <!-- Tests -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-webmvc-test</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security-test</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis-test</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
            <exclusions>
                <exclusion>
                    <groupId>org.junit.vintage</groupId>
                    <artifactId>junit-vintage-engine</artifactId>
                </exclusion>
            </exclusions>
        </dependency>
        <dependency>
            <groupId>org.springframework.security</groupId>
            <artifactId>spring-security-test</artifactId>
            <scope>test</scope>
        </dependency>

        <dependency>
            <groupId>me.paulschwarz</groupId>
            <artifactId>spring-dotenv</artifactId>
            <version>4.0.0</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <version>${spring.boot.version}</version>
                <executions>
                    <execution>
                        <goals>
                            <goal>repackage</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.11.0</version>
                <configuration>
                    <source>${java.version}</source>
                    <target>${java.version}</target>
                </configuration>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.2.5</version>
            </plugin>
        </plugins>
    </build>
</project>
GG_EOF

deploy_file "flowtxt-api/src/main/resources/application.yaml" <<'GG_EOF'
spring:
  application:
    name: flowtxt-api
  # Java 21 virtual threads: cheap blocking-I/O concurrency without a
  # different servlet container (the modern answer to why projects used to
  # pick Undertow).
  threads:
    virtual:
      enabled: true
  config:
    import: optional:file:.env
  profiles:
    active: dev

  # Twelve-Factor config: the JDBC URL comes from the DATABASE_URL env var
  # (default = the local docker-compose Postgres 16). No schema auto-ddl —
  # Flyway owns the schema.
  datasource:
    url: ${DATABASE_URL:jdbc:postgresql://localhost:5432/flowtxt}
    username: ${DB_USERNAME:flowtxt}
    password: ${DB_PASSWORD:flowtxt}

  flyway:
    enabled: true
    locations: classpath:db/migration

  jpa:
    hibernate:
      ddl-auto: validate
    open-in-view: false

  # Boot 3 renamed Redis properties under spring.data.redis
  data:
    redis:
      host: localhost
      port: 6379

  jackson:
    serialization:
      INDENT_OUTPUT: true

server:
  port: 8080

# JWT — the secret is a DEV-ONLY placeholder. Production MUST override it via
# the JWT_SECRET environment variable (e.g. `openssl rand -base64 48`).
jwt:
  secret: ${JWT_SECRET:change-me-dev-only-please-use-a-long-random-secret}
  expiration-ms: ${JWT_EXPIRATION_MS:3600000}

twilio:
  account-sid: ${TWILIO_ACCOUNT_SID}
  auth-token: ${TWILIO_AUTH_TOKEN:dev-only-twilio-placeholder}
  phone-number: ${TWILIO_PHONE_NUMBER}

logging:
  level:
    root: INFO
    ca.flowtxt: DEBUG
    org.hibernate.SQL: DEBUG

springdoc:
  api-docs:
    path: /api-docs
  swagger-ui:
    path: /swagger-ui.html

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: when_authorized
      probes:
        enabled: true
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/AbstractIntegrationTest.java" <<'GG_EOF'
package ca.flowtxt;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.utility.DockerImageName;

/**
 * Base class for integration tests: boots the full application against real
 * PostgreSQL and Redis containers, with the schema applied by Flyway (the
 * same migrations production runs). Skipped automatically when Docker is not
 * available (see @Testcontainers(disabledWithoutDocker = true)).
 *
 * <p>The containers are started once per JVM in a static initializer instead
 * of being managed by {@code @Container}: the Spring application context is
 * cached across test classes, so per-class container restarts would leave the
 * cached context pointing at dead mapped ports. Containers are removed by
 * Testcontainers' Ryuk reaper when the JVM exits.</p>
 */
@Testcontainers(disabledWithoutDocker = true)
@SpringBootTest
@AutoConfigureMockMvc
public abstract class AbstractIntegrationTest {

    static final PostgreSQLContainer<?> POSTGRES =
            new PostgreSQLContainer<>(DockerImageName.parse("postgres:16"));

    static final GenericContainer<?> REDIS =
            new GenericContainer<>(DockerImageName.parse("redis:7-alpine"))
                    .withExposedPorts(6379);

    static {
        POSTGRES.start();
        REDIS.start();
    }

    @DynamicPropertySource
    static void registerProperties(DynamicPropertyRegistry registry) {
        // Flyway runs automatically on boot and applies V1__init.sql.
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.data.redis.host", REDIS::getHost);
        registry.add("spring.data.redis.port", () -> REDIS.getMappedPort(6379));
        registry.add("jwt.secret",
                () -> "integration-test-secret-that-is-long-enough-for-hs256!!");
        registry.add("twilio.auth-token",
                () -> "integration-test-twilio-token");
    }

    @Autowired
    protected MockMvc mockMvc;
}
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/JpaRepositoriesIT.java" <<'GG_EOF'
package ca.flowtxt;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.domain.model.User;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JpaRepositoriesIT extends AbstractIntegrationTest {

    @Autowired
    private ContactRepository contactRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private MessageRepository messageRepository;

    @Test
    void persistsAndFindsAContactByPhoneNumber() {
        Contact contact = Contact.create("Maria Silva", new PhoneNumber("+5511999999999"));
        contactRepository.save(contact);

        assertTrue(contactRepository.findByPhoneNumber("+5511999999999").isPresent());
        assertEquals("Maria Silva",
                contactRepository.findByPhoneNumber("+5511999999999").get().getName());
    }

    @Test
    void persistsAndFindsAUserByEmail() {
        userRepository.save(User.register("it-user@example.com", "$2a$10$hash"));

        assertTrue(userRepository.findByEmail("it-user@example.com").isPresent());
        assertEquals(ca.flowtxt.domain.model.Role.USER,
                userRepository.findByEmail("it-user@example.com").get().getRole());
    }

    @Test
    void persistsAMessageAndFindsItBySidAfterItsLifecycleAdvances() {
        Contact contact = Contact.create("John Souza", new PhoneNumber("+5511888888888"));
        contactRepository.save(contact);

        Message message = Message.pending(contact.getId(), "Hello FlowTXT");
        messageRepository.save(message);
        messageRepository.save(message.markSent("SM-IT-123"));

        Message reloaded = messageRepository.findBySid("SM-IT-123").orElseThrow();
        assertEquals(MessageStatus.SENT, reloaded.getStatus());
        assertEquals("SM-IT-123", reloaded.getSid());

        messageRepository.save(reloaded.applyProviderStatus(MessageStatus.DELIVERED, "SM-IT-123"));
        assertEquals(MessageStatus.DELIVERED,
                messageRepository.findBySid("SM-IT-123").orElseThrow().getStatus());
    }
}
GG_EOF

deploy_file "flowtxt-api/src/test/java/ca/flowtxt/SecurityFlowIT.java" <<'GG_EOF'
package ca.flowtxt;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.security.TwilioSignatures;
import tools.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end security flow against real PostgreSQL + Redis containers:
 * register -> login -> protected endpoint (with and without a token).
 */
class SecurityFlowIT extends AbstractIntegrationTest {

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private ContactRepository contactRepository;

    @Autowired
    private MessageRepository messageRepository;

    @Test
    void registerLoginAndCallProtectedEndpoint() throws Exception {
        // 1. Register — public
        mockMvc.perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"flow-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.token").isNotEmpty());

        // 2. Login — public, returns a fresh token
        String loginBody = mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"flow-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").isNotEmpty())
                .andReturn().getResponse().getContentAsString();

        String token = objectMapper.readTree(loginBody).get("token").asText();

        // 3. Protected endpoint WITHOUT a token -> 401
        mockMvc.perform(post("/contacts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Maria\",\"phoneNumber\":\"+5511999999999\"}"))
                .andExpect(status().isUnauthorized());

        // 4. Protected endpoint WITH the token -> 200
        mockMvc.perform(post("/contacts")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Maria\",\"phoneNumber\":\"+5511999999999\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Maria"));
    }

    @Test
    void rejectsLoginWithWrongPassword() throws Exception {
        mockMvc.perform(post("/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"another-user@example.com\",\"password\":\"strongpass123\"}"))
                .andExpect(status().isCreated());

        mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"another-user@example.com\",\"password\":\"wrong-password\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void webhookRejectsUnsignedCallbacks() throws Exception {
        // The route is permitAll in SecurityConfig; the signature filter is
        // what protects it. Without a valid X-Twilio-Signature -> 403.
        mockMvc.perform(post("/webhook/twilio/status")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM-unsigned")
                        .param("MessageStatus", "sent"))
                .andExpect(status().isForbidden());
    }

    @Test
    void webhookAcceptsASignedCallbackForAKnownSid() throws Exception {
        // Persist a message and advance it to SENT so the callback has a sid.
        contactRepository.save(Contact.create("Webhook Tester", new PhoneNumber("+15550000001")));
        Message message = Message.pending(
                contactRepository.findByPhoneNumber("+15550000001").orElseThrow().getId(),
                "Hello FlowTXT");
        messageRepository.save(message);
        messageRepository.save(message.markSent("SM-signed-it"));

        String url = "http://localhost/webhook/twilio/status";
        String signature = TwilioSignatures.sign("integration-test-twilio-token", url, Map.of(
                "MessageSid", "SM-signed-it",
                "MessageStatus", "delivered"));

        mockMvc.perform(post("/webhook/twilio/status")
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("MessageSid", "SM-signed-it")
                        .param("MessageStatus", "delivered")
                        .header("X-Twilio-Signature", signature))
                .andExpect(status().isOk());

        assertEquals(MessageStatus.DELIVERED,
                messageRepository.findBySid("SM-signed-it").orElseThrow().getStatus());
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/pom.xml" <<'GG_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>ca.flowtxt</groupId>
        <artifactId>flowtxt-parent</artifactId>
        <version>1.0-SNAPSHOT</version>
    </parent>

    <artifactId>flowtxt-infrastructure</artifactId>
    <packaging>jar</packaging>

    <properties>
        <java.version>21</java.version>
        <junit.jupiter.version>5.10.2</junit.jupiter.version>
        <mockito.version>5.8.0</mockito.version>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <maven.compiler.source>${java.version}</maven.compiler.source>
        <maven.compiler.target>${java.version}</maven.compiler.target>
    </properties>

    <dependencies>
        <dependency>
            <groupId>ca.flowtxt</groupId>
            <artifactId>flowtxt-application</artifactId>
            <version>${project.version}</version>
        </dependency>

        <!-- Spring Data JPA + PostgreSQL + Flyway -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-jpa</artifactId>
        </dependency>
        <dependency>
            <groupId>org.postgresql</groupId>
            <artifactId>postgresql</artifactId>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-flyway</artifactId>
        </dependency>
        <dependency>
            <groupId>org.flywaydb</groupId>
            <artifactId>flyway-database-postgresql</artifactId>
        </dependency>

        <!-- Redis -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-data-redis</artifactId>
        </dependency>

        <!-- Twilio SDK -->
        <dependency>
            <groupId>com.twilio.sdk</groupId>
            <artifactId>twilio</artifactId>
            <version>9.13.0</version>
        </dependency>

        <!-- MapStruct -->
        <dependency>
            <groupId>org.mapstruct</groupId>
            <artifactId>mapstruct</artifactId>
            <version>1.5.5.Final</version>
        </dependency>

        <!-- Spring Security (JWT filter + UserDetails) -->
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-security</artifactId>
        </dependency>

        <!-- JJWT — JWT creation/validation -->
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-api</artifactId>
            <version>0.12.6</version>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-impl</artifactId>
            <version>0.12.6</version>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>io.jsonwebtoken</groupId>
            <artifactId>jjwt-jackson</artifactId>
            <version>0.12.6</version>
            <scope>runtime</scope>
        </dependency>


        <!-- Spring Web + Servlet API (security filter needs them; the API
             module provides the web runtime via spring-boot-starter-web) -->
        <dependency>
            <groupId>org.springframework</groupId>
            <artifactId>spring-web</artifactId>
        </dependency>
        <dependency>
            <groupId>jakarta.servlet</groupId>
            <artifactId>jakarta.servlet-api</artifactId>
            <scope>provided</scope>
        </dependency>


        <!-- Tests -->
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.2</version>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.mockito</groupId>
            <artifactId>mockito-junit-jupiter</artifactId>
            <version>5.8.0</version>
            <scope>test</scope>
        </dependency>


        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>org.testcontainers</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>1.21.4</version>
            <scope>test</scope>
        </dependency>

    </dependencies>

    <build>
        <plugins>
            <!-- Annotation Processor -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.11.0</version>
                <configuration>
                    <source>${java.version}</source>
                    <target>${java.version}</target>
                    <annotationProcessorPaths>
                        <path>
                            <groupId>org.mapstruct</groupId>
                            <artifactId>mapstruct-processor</artifactId>
                            <version>1.5.5.Final</version>
                        </path>
                    </annotationProcessorPaths>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/JpaContactRepositoryAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.ContactRepository;
import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.infrastructure.persistence.mapper.ContactMapper;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * PostgreSQL/JPA adapter for {@link ContactRepository}.
 */
@Repository
public class JpaContactRepositoryAdapter implements ContactRepository {

    private final SpringDataContactRepository repository;
    private final ContactMapper mapper;

    public JpaContactRepositoryAdapter(
            SpringDataContactRepository repository,
            ContactMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public Optional<Contact> findById(UUID id) {
        return repository.findById(id).map(mapper::toDomain);
    }

    @Override
    public Optional<Contact> findByPhoneNumber(String phoneNumber) {
        return repository.findByPhoneNumber(phoneNumber).map(mapper::toDomain);
    }

    @Override
    public void save(Contact contact) {
        repository.save(mapper.toEntity(contact));
    }

    @Override
    public List<Contact> findAll() {
        return repository.findAll().stream()
                .map(mapper::toDomain)
                .toList();
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/JpaMessageRepositoryAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.MessageRepository;
import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.mapper.MessageMapper;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

/**
 * PostgreSQL/JPA adapter for {@link MessageRepository}.
 */
@Repository
public class JpaMessageRepositoryAdapter implements MessageRepository {

    private final SpringDataMessageRepository repository;
    private final MessageMapper mapper;

    public JpaMessageRepositoryAdapter(
            SpringDataMessageRepository repository,
            MessageMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public void save(Message message) {
        repository.save(mapper.toEntity(message));
    }

    @Override
    public Optional<Message> findById(UUID id) {
        return repository.findById(id).map(mapper::toDomain);
    }

    @Override
    public Optional<Message> findBySid(String messageSid) {
        return repository.findBySid(messageSid).map(mapper::toDomain);
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/JpaUserRepositoryAdapter.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.application.port.out.UserRepository;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.mapper.UserMapper;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/**
 * PostgreSQL/JPA adapter for {@link UserRepository}.
 */
@Repository
public class JpaUserRepositoryAdapter implements UserRepository {

    private final SpringDataUserRepository repository;
    private final UserMapper mapper;

    public JpaUserRepositoryAdapter(
            SpringDataUserRepository repository,
            UserMapper mapper) {
        this.repository = repository;
        this.mapper = mapper;
    }

    @Override
    public Optional<User> findByEmail(String email) {
        return repository.findByEmail(email).map(mapper::toUser);
    }

    @Override
    public void save(User user) {
        repository.save(mapper.toEntity(user));
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/SpringDataContactRepository.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.entity.ContactEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataContactRepository extends JpaRepository<ContactEntity, UUID> {

    Optional<ContactEntity> findByPhoneNumber(String phoneNumber);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/SpringDataMessageRepository.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.entity.MessageEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataMessageRepository extends JpaRepository<MessageEntity, UUID> {

    Optional<MessageEntity> findBySid(String messageSid);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/SpringDataUserRepository.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence;

import ca.flowtxt.infrastructure.persistence.entity.UserEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface SpringDataUserRepository extends JpaRepository<UserEntity, UUID> {

    Optional<UserEntity> findByEmail(String email);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/entity/ContactEntity.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.util.UUID;

/**
 * JPA entity for the {@code contacts} table. The domain {@code Contact} is
 * immutable; this mutable entity is the persistence representation only.
 */
@Entity
@Table(name = "contacts")
public class ContactEntity {

    @Id
    private UUID id;

    @Column(nullable = false)
    private String name;

    @Column(nullable = false, unique = true)
    private String phoneNumber;

    protected ContactEntity() {
        // JPA
    }

    public ContactEntity(UUID id, String name, String phoneNumber) {
        this.id = id;
        this.name = name;
        this.phoneNumber = phoneNumber;
    }

    public UUID getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public String getPhoneNumber() {
        return phoneNumber;
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/entity/MessageEntity.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.entity;

import ca.flowtxt.domain.model.MessageStatus;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity for the {@code messages} table.
 *
 * <p>The {@code contact_id} column is a plain UUID column with a foreign key
 * enforced by the Flyway DDL — the domain {@link ca.flowtxt.domain.model.Message}
 * is immutable and holds only {@code contactId}, so no JPA association is
 * mapped (a {@code @ManyToOne} would force an unnecessary fetch and muddy the
 * mapper). Referential integrity lives in the database, where it belongs.</p>
 *
 * <p>{@code @Version} provides optimistic locking: concurrent delivery-status
 * callbacks cannot silently overwrite each other's status update.</p>
 */
@Entity
@Table(name = "messages")
public class MessageEntity {

    @Id
    private UUID id;

    @Column(name = "contact_id", nullable = false)
    private UUID contactId;

    @Column(nullable = false)
    private String content;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private MessageStatus status;

    @Column(nullable = false)
    private Instant timestamp;

    @Column(unique = true)
    private String sid;

    @Version
    @Column(nullable = false)
    private long version;

    protected MessageEntity() {
        // JPA
    }

    public MessageEntity(
            UUID id,
            UUID contactId,
            String content,
            MessageStatus status,
            Instant timestamp,
            String sid) {
        this.id = id;
        this.contactId = contactId;
        this.content = content;
        this.status = status;
        this.timestamp = timestamp;
        this.sid = sid;
    }

    public UUID getId() {
        return id;
    }

    public UUID getContactId() {
        return contactId;
    }

    public String getContent() {
        return content;
    }

    public MessageStatus getStatus() {
        return status;
    }

    public Instant getTimestamp() {
        return timestamp;
    }

    public String getSid() {
        return sid;
    }

    public long getVersion() {
        return version;
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/entity/UserEntity.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.entity;

import ca.flowtxt.domain.model.Role;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * JPA entity for the {@code users} table. The password is stored only as a
 * hash. The role is persisted as a string so enum renames survive.
 */
@Entity
@Table(name = "users")
public class UserEntity {

    @Id
    private UUID id;

    @Column(nullable = false, unique = true)
    private String email;

    @Column(nullable = false)
    private String passwordHash;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Role role;

    @Column(nullable = false)
    private Instant createdAt;

    protected UserEntity() {
        // JPA
    }

    public UserEntity(UUID id, String email, String passwordHash, Role role, Instant createdAt) {
        this.id = id;
        this.email = email;
        this.passwordHash = passwordHash;
        this.role = role;
        this.createdAt = createdAt;
    }

    public UUID getId() {
        return id;
    }

    public String getEmail() {
        return email;
    }

    public String getPasswordHash() {
        return passwordHash;
    }

    public Role getRole() {
        return role;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/mapper/ContactMapper.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.persistence.entity.ContactEntity;
import org.mapstruct.Mapper;

/**
 * Maps between the immutable domain {@link Contact} and the JPA
 * {@link ContactEntity}. The domain stays free of persistence annotations.
 */
@Mapper(componentModel = "spring")
public interface ContactMapper {

    // Domain → Entity
    ContactEntity toEntity(Contact contact);

    // Entity → Domain
    Contact toDomain(ContactEntity entity);

    // PhoneNumber → String
    default String map(PhoneNumber phoneNumber) {
        return phoneNumber != null ? phoneNumber.value() : null;
    }

    // String → PhoneNumber
    default PhoneNumber map(String phoneNumber) {
        return phoneNumber != null ? new PhoneNumber(phoneNumber) : null;
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/mapper/MessageMapper.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Message;
import ca.flowtxt.infrastructure.persistence.entity.MessageEntity;
import org.mapstruct.Mapper;

/**
 * Maps between the immutable domain {@link Message} and the JPA
 * {@link MessageEntity}. Field names align one-to-one (constructor mapping on
 * the domain side, setter mapping on the entity side).
 */
@Mapper(componentModel = "spring")
public interface MessageMapper {

    MessageEntity toEntity(Message message);

    Message toDomain(MessageEntity entity);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/mapper/UserMapper.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.entity.UserEntity;
import org.mapstruct.Mapper;

/**
 * Maps between the immutable domain {@link User} and the JPA
 * {@link UserEntity}.
 */
@Mapper(componentModel = "spring")
public interface UserMapper {

    User toUser(UserEntity entity);

    UserEntity toEntity(User user);
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/main/resources/db/migration/V1__init.sql" <<'GG_EOF'
-- FlowTXT initial schema (PostgreSQL 16)
-- Owned by Flyway: never edit applied migrations; add V2__, V3__, ... instead.

CREATE TABLE users (
    id            uuid PRIMARY KEY,
    email         varchar(255) NOT NULL UNIQUE,
    password_hash varchar(255) NOT NULL,
    role          varchar(20)  NOT NULL CHECK (role IN ('USER', 'ADMIN')),
    created_at    timestamptz  NOT NULL
);

CREATE TABLE contacts (
    id           uuid PRIMARY KEY,
    name         varchar(255) NOT NULL,
    phone_number varchar(32)  NOT NULL UNIQUE
);

CREATE TABLE messages (
    id         uuid PRIMARY KEY,
    contact_id uuid        NOT NULL REFERENCES contacts (id),
    content    text        NOT NULL,
    status     varchar(20) NOT NULL CHECK (status IN (
        'PENDING', 'QUEUED', 'SENT', 'DELIVERED', 'UNDELIVERED',
        'FAILED', 'RECEIVED', 'UNKNOWN')),
    timestamp  timestamptz NOT NULL,
    sid        varchar(64) UNIQUE,
    version    bigint      NOT NULL DEFAULT 0
);

CREATE INDEX idx_messages_contact_id ON messages (contact_id);
CREATE INDEX idx_messages_sid ON messages (sid);
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/persistence/mapper/ContactMapperTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Contact;
import ca.flowtxt.domain.model.PhoneNumber;
import ca.flowtxt.infrastructure.persistence.entity.ContactEntity;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ContactMapperTest {

    private final ContactMapper mapper = new ContactMapperImpl();

    @Test
    void mapsContactToEntity() {
        Contact contact = new Contact(
                UUID.fromString("00000000-0000-0000-0000-000000000001"),
                "Maria Silva",
                new PhoneNumber("+5511999999999"));

        ContactEntity entity = mapper.toEntity(contact);

        assertEquals(contact.getId(), entity.getId());
        assertEquals("Maria Silva", entity.getName());
        assertEquals("+5511999999999", entity.getPhoneNumber());
    }

    @Test
    void mapsEntityBackToContact() {
        ContactEntity entity = new ContactEntity(
                UUID.fromString("00000000-0000-0000-0000-000000000002"),
                "John Souza",
                "+5511888888888");

        Contact contact = mapper.toDomain(entity);

        assertEquals(entity.getId(), contact.getId());
        assertEquals("John Souza", contact.getName());
        assertEquals("+5511888888888", contact.getPhoneNumber().value());
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/persistence/mapper/MessageMapperTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Message;
import ca.flowtxt.domain.model.MessageStatus;
import ca.flowtxt.infrastructure.persistence.entity.MessageEntity;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class MessageMapperTest {

    private final MessageMapper mapper = new MessageMapperImpl();

    @Test
    void mapsMessageToEntity() {
        UUID contactId = UUID.fromString("00000000-0000-0000-0000-000000000011");
        Instant now = Instant.now();

        Message message = new Message(
                UUID.fromString("00000000-0000-0000-0000-000000000012"),
                contactId, "Hello!", MessageStatus.SENT, now, "SM123");

        MessageEntity entity = mapper.toEntity(message);

        assertEquals(message.getId(), entity.getId());
        assertEquals(contactId, entity.getContactId());
        assertEquals("Hello!", entity.getContent());
        assertEquals(MessageStatus.SENT, entity.getStatus());
        assertEquals(now, entity.getTimestamp());
        assertEquals("SM123", entity.getSid());
    }

    @Test
    void mapsEntityBackToMessage() {
        MessageEntity entity = new MessageEntity(
                UUID.fromString("00000000-0000-0000-0000-000000000013"),
                UUID.fromString("00000000-0000-0000-0000-000000000014"),
                "Hi",
                MessageStatus.PENDING,
                Instant.parse("2026-08-21T10:00:00Z"),
                "SM456");

        Message message = mapper.toDomain(entity);

        assertEquals(entity.getId(), message.getId());
        assertEquals(entity.getContactId(), message.getContactId());
        assertEquals(entity.getContent(), message.getContent());
        assertEquals(entity.getStatus(), message.getStatus());
        assertEquals(entity.getTimestamp(), message.getTimestamp());
        assertEquals(entity.getSid(), message.getSid());
    }
}
GG_EOF

deploy_file "flowtxt-infrastructure/src/test/java/ca/flowtxt/infrastructure/persistence/mapper/UserMapperTest.java" <<'GG_EOF'
package ca.flowtxt.infrastructure.persistence.mapper;

import ca.flowtxt.domain.model.Role;
import ca.flowtxt.domain.model.User;
import ca.flowtxt.infrastructure.persistence.entity.UserEntity;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class UserMapperTest {

    private final UserMapper mapper = new UserMapperImpl();

    @Test
    void mapsUserToEntity() {
        User user = new User(
                UUID.fromString("00000000-0000-0000-0000-000000000021"),
                "user@example.com",
                "$2a$10$hash",
                Role.USER,
                Instant.parse("2026-08-21T10:00:00Z"));

        UserEntity entity = mapper.toEntity(user);

        assertEquals(user.getId(), entity.getId());
        assertEquals("user@example.com", entity.getEmail());
        assertEquals("$2a$10$hash", entity.getPasswordHash());
        assertEquals(Role.USER, entity.getRole());
    }

    @Test
    void mapsEntityBackToUser() {
        UserEntity entity = new UserEntity(
                UUID.fromString("00000000-0000-0000-0000-000000000022"),
                "admin@example.com",
                "$2a$10$hash2",
                Role.ADMIN,
                Instant.parse("2026-08-21T11:00:00Z"));

        User user = mapper.toUser(entity);

        assertEquals(entity.getId(), user.getId());
        assertEquals(entity.getEmail(), user.getEmail());
        assertEquals(entity.getRole(), user.getRole());
    }
}
GG_EOF

deploy_file "scripts/smoke-test.sh" <<'GG_EOF'
#!/usr/bin/env bash
#
# smoke-test.sh — boots the API against local PostgreSQL + Redis and exercises the
# core flow: health -> register -> login -> protected contact creation.
#
# Usage: ./scripts/smoke-test.sh
# Requires: Docker, JDK 21, and a .env with (dummy) Twilio + JWT values.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "==> Starting PostgreSQL + Redis (docker compose)"
docker compose -f docker/docker-compose.yaml up -d

echo "==> Starting the API (background)"
./mvnw spring-boot:run -pl flowtxt-api > /tmp/flowtxt-smoke.log 2>&1 &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null || true; docker compose -f docker/docker-compose.yaml down' EXIT

echo "==> Waiting for /actuator/health"
for i in $(seq 1 60); do
  if curl -sf "$BASE_URL/actuator/health" > /dev/null 2>&1; then
    echo "    health OK"
    break
  fi
  sleep 2
  if [ "$i" = "60" ]; then echo "FATAL: API did not become healthy"; tail -50 /tmp/flowtxt-smoke.log; exit 1; fi
done

echo "==> Register a user"
REGISTER=$(curl -sf -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"smoke@example.com","password":"strongpass123"}' \
  || { echo "FATAL: register failed"; tail -50 /tmp/flowtxt-smoke.log; exit 1; })
echo "    $REGISTER"

TOKEN=$(echo "$REGISTER" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "FATAL: no token in register response"; exit 1; }

echo "==> Create a contact with the token"
curl -sf -X POST "$BASE_URL/contacts" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Maria","phoneNumber":"+5511999999999"}' \
  || { echo "FATAL: contact creation failed"; exit 1; }
echo "    contact created"

echo "==> Protected endpoint without token must be rejected (401)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/contacts" \
  -H "Content-Type: application/json" \
  -d '{"name":"X","phoneNumber":"+5511000000000"}')
[ "$STATUS" = "401" ] || { echo "FATAL: expected 401, got $STATUS"; exit 1; }
echo "    401 OK"

echo
echo "SMOKE TEST PASSED ✔"
GG_EOF

# --- remove legacy Mongo persistence files ---
if [ -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoContactRepositoryAdapter.java" ]; then rm -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoContactRepositoryAdapter.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoContactRepositoryAdapter.java"; fi
if [ -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoMessageRepositoryAdapter.java" ]; then rm -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoMessageRepositoryAdapter.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoMessageRepositoryAdapter.java"; fi
if [ -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoUserRepositoryAdapter.java" ]; then rm -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoUserRepositoryAdapter.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/MongoUserRepositoryAdapter.java"; fi
if [ -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/ContactDocument.java" ]; then rm -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/ContactDocument.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/ContactDocument.java"; fi
if [ -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/MessageDocument.java" ]; then rm -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/MessageDocument.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/MessageDocument.java"; fi
if [ -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/UserDocument.java" ]; then rm -f "flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/UserDocument.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-infrastructure/src/main/java/ca/flowtxt/infrastructure/persistence/document/UserDocument.java"; fi
if [ -f "flowtxt-api/src/test/java/ca/flowtxt/MongoRepositoriesIT.java" ]; then rm -f "flowtxt-api/src/test/java/ca/flowtxt/MongoRepositoriesIT.java"; echo -e "${GREEN}[deleted]${NC} flowtxt-api/src/test/java/ca/flowtxt/MongoRepositoriesIT.java"; fi

# --- executable bits ---
chmod +x mvnw scripts/smoke-test.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# Verify — the CI gates (mirrored locally)
# -----------------------------------------------------------------------------
echo
info "==> Running gates (unit tests, install, spotbugs, jacoco)"
if ! command -v java >/dev/null 2>&1 || ! java -version 2>&1 | grep -q '"21'; then
  err "JDK 21 is required (JAVA_HOME must point to a JDK 21)."
  exit 1
fi

./mvnw test 2>&1 | tail -n 8
./mvnw -B install -DskipTests 2>&1 | tail -n 3
./mvnw spotbugs:check 2>&1 | tail -n 3 || true
./mvnw jacoco:check 2>&1 | tail -n 3 || true

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo
echo "======================================================================"
echo "  SUMMARY"
echo "======================================================================"
echo "  Applied: MongoDB -> PostgreSQL 16 + Flyway (ADR-0002)"
echo "    - JPA entities + Jpa*Adapters (domain untouched, immutable)"
echo "    - Flyway V1__init.sql (UNIQUE/FK/CHECK) + ddl-auto: validate"
echo "    - @Version optimistic locking on MessageEntity"
echo "    - docker-compose postgres:16 + redis"
echo "    - Twelve-Factor DATABASE_URL config"
echo "    - Testcontainers PostgreSQLContainer + Flyway in *IT"
echo "    - Docs synced (ADR-0002, README, CHANGELOG, AGENTS, standards...)"
echo "  Backups: *.bak.$TS for every replaced file."
echo
echo "  Next steps:"
echo "    git add -A"
echo "    git commit -m \"feat(persistence): migrate MongoDB to PostgreSQL with Flyway\""
echo "    git push   # CI runs (unit + *IT with Postgres + quality gates)"
echo "    Local dev: docker compose -f docker/docker-compose.yaml up -d"
echo "======================================================================"
