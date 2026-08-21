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
| Adapters | `<Technology><Port>Adapter` | `MongoUserRepositoryAdapter`, `TwilioSmsAdapter` |
| Ports | `<Concept><Kind>` (Repository/Service/UseCase/Hasher) | `SmsService`, `PasswordHasher` |
| Methods / variables | camelCase | `sendMessage()`, `passwordHash` |
| Constants / enums | UPPER_SNAKE_CASE | `MIN_PASSWORD_LENGTH`, `MessageStatus.SENT` |
| Tests (unit) | `*Test.java` | `JwtServiceTest` |
| Tests (integration) | `*IT.java` | `SecurityFlowIT` |
| DTOs (records) | `<Noun>Request` / `<Noun>Response` | `RegisterUserRequest`, `AuthResponse` |

Name for **what it is or does**, not the implementation: `ContactRepository`, not `MongoDao`.

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
├── persistence/        Mongo repositories (Spring Data), documents, mappers
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
| `domain/` | **None** — no Spring, Twilio, JJWT, MongoDB |
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

## 6. Persistence (MongoDB) & cache (Redis)

- One Spring Data repository per aggregate; explicit mappers (MapStruct) between documents and
  domain models — domain models never leak persistence annotations.
- Prefer explicit repository interfaces (ports) over exposing `MongoRepository` to the
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
| Integration | JUnit 5 + Testcontainers (`*IT`) | Mongo + Redis containers, real adapters, security flow |

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
