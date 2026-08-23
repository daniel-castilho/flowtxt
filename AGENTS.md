# AGENTS.md

FlowTXT — an SMS delivery backend built with **Java 21 + Spring Boot 4.1** as a strict
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

- `SendMessageUseCaseImpl` persists twice by design (PENDING audit trail, then SENT/FAILED);
  provider failures are handled with a FAILED transition since 2026-08-21.
- `jjwt-jackson` still pulls Jackson 2 transitively for token serialization while the app runs Jackson 3; swap modules when jjwt ships a Jackson 3-compatible one.

> Resolved 2026-08-22 (latest): api→infrastructure coupling beyond the composition root is gone —
> `AuthController` no longer injects the infrastructure `JwtService`; register/login go through
> the application port `AuthenticationTokenPort`, use cases return an `AuthResult(user, token)`,
> and `GlobalExceptionHandler` moved to `flowtxt-infrastructure` (final state). Removed from
> this list. See CHANGELOG.

> Resolved 2026-08-21 (latest): `PhoneNumber` now enforces strict E.164 in the domain value
> object (`+[1-9]\d{1,14}`); the DTO pattern mirrors it. Removed from this list. See CHANGELOG
> and tasks/flowtxt-excellence-backlog.md #3.

> Resolved 2026-08-21 (latest): `/auth/login` rate limiting shipped — Redis-backed fixed window
> per client IP (`RateLimitFilter` + `FixedWindowRateLimiter` + `RateLimitProperties`),
> 429 + `Retry-After`, fail-open on Redis outage. Removed from this list. See CHANGELOG and
> tasks/flowtxt-excellence-backlog.md #2.

> Resolved 2026-08-21 (later): the message adapter was silently defeating `@Version` (immutable
> domain remapped to fresh entities, version reset to 0) — fixed via load-then-apply persistence;
> IT classes now truncate shared PostgreSQL tables before each test, killing order-dependent
> duplicate-key collisions. See CHANGELOG ("Fixed") and docs/lessons.md.

> Resolved 2026-08-21 (latest): fail-fast config validation at boot shipped (12-factor factor 3):
> `StartupConfigValidator` + typed `JwtProperties`/`TwilioProperties`; aggregated boot report,
> dev placeholder secret and missing Twilio credentials rejected outside dev. Production must run
> with `SPRING_PROFILES_ACTIVE=prod`. See CHANGELOG and docs/twelve-factor.md.

> Resolved 2026-08-21 (latest): `CacheService.put` now requires a positive TTL (port signature
> makes unbounded keys unrepresentable — coding-standards §6); expiry covered by unit test and a
> real-Redis IT. See CHANGELOG.

> Resolved 2026-08-21 (latest): release convention shipped (12-factor factor 5) — GHCR push per
> `main` commit (immutable `sha-<short>` + moving `edge`), `v*` annotated tags publish semver
> image tags and GitHub Releases with jar + SBOM. Convention lives in README "Releases &
> Rollout". See CHANGELOG and docs/twelve-factor.md.

> Resolved 2026-08-21 (latest): `scripts/` admin-process convention shipped (12-factor factor
> 12): idempotent dev seeding via the REST API, psql wrapper, smoke test; duplicate contact
> phones now answer 409 instead of a raw 500. See CHANGELOG, scripts/README.md.

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
