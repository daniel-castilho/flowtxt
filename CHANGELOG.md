# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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

### Removed
- Dead code: orphan `ca.flowtxt.persistence.MongoContactRepository` interface (duplicated
  `SpringDataContactRepository`, never referenced) and the unused
  `TwilioDeliveryStatusRequest` DTO; unused imports cleaned up.

### Security
- The API is no longer wide open: contacts and message endpoints now require a valid JWT.
