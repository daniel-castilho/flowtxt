# Changelog

All notable changes to this project are documented in this file. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Runbook `docs/ci-vulnerability-gates.md`**: portable recipe (symptoms → root causes →
  copy-paste fixes → verification checklist) for the two supply-chain gates — the
  trivy-action SARIF severity gotcha and NVD-outage-resilient Dependency Check — so other
  projects hitting the same GitHub Actions failures can apply them directly.

### Changed
- **Repository hygiene after the excellence merge**: removed the obsolete "AuthController injects
  infrastructure `JwtService`" item from AGENTS.md Known Technical Debt (the coupling is gone —
  auth flows through the `AuthenticationTokenPort` application port and use cases return
  `AuthResult`; the resolved entry now records this); deleted the accidentally committed
  `.excellence-backup-20260823T000151Z/` snapshot (28 files of pre-change copies) and added
  `.excellence-backup*/` to `.gitignore`; fixed a duplicated `TestRestTemplate` import in
  `AbstractHttpIntegrationTest` left over from the Boot 4 module migration; corrected remaining
  documentation drift (`docs/testing-playbook.md` said Spring Boot 3.5, `docs/lessons.md`
  described the Testcontainers stack as Mongo instead of PostgreSQL).

### Fixed
- **CI red on `main` for two independent reasons**:
  - The Trivy image scan failed on fixable MEDIUM CVEs although the policy is
    HIGH/CRITICAL — with `format: sarif`, trivy-action ignores the `severity`
    filter for both the report and the exit code
    ([aquasecurity/trivy-action#309](https://github.com/aquasecurity/trivy-action/issues/309)).
    The pipeline now runs a non-blocking full-SARIF pass (Security-tab advisory
    trail, unchanged) plus a separate table-format gate whose exit code only
    fires on fixable HIGH/CRITICAL findings.
  - The OWASP Dependency Check build gate broke whenever the NVD API answered
    429/503 (ongoing instability since its June 2026 schema migration), aborting
    mid-update and sometimes corrupting the cached H2 mirror. The plugin now
    sets `failOnError=false` so an unreachable NVD degrades to scanning against
    the cached mirror instead of failing CI; vulnerability reporting stays
    fail-soft by design (`failBuildOnCVSS=11`) and the image remains gated hard
    by Trivy.
- **The reactor could not even read its POMs**: commit `a40fbd1` declared Jackson 3 under the
  non-existent `tools.jackson:jackson-annotations` / `tools.jackson:jackson-databind`
  coordinates; the Boot 4 BOM manages `tools.jackson.core:jackson-databind` while
  `jackson-annotations` stays on its legacy `com.fasterxml.jackson.core` coordinates (2.x line).
  Coordinates corrected and the misleading comment replaced. Because the broken POM masked the
  compiler, four further Boot 4 migration breakages surfaced one after another: the actuator
  health API moved to `org.springframework.boot.health.contributor` (`spring-boot-health`
  module, already transitive via `spring-boot-starter-actuator`);
  `TestRestTemplate` moved to the new Boot 4 `spring-boot-resttestclient` module (added as a
  test-scoped, BOM-managed dependency of flowtxt-api — explicitly approved);
  `RateLimitFilterTest` still asserted a direct `setStatus(429)` that the filter delegated to
  `RestErrorResponseWriter` back in `603a3e9` (assertion updated, 429 coverage kept via the
  writer verification); and the controller slice lacked beans for
  `RestAuthenticationEntryPoint`/`RestAccessDeniedHandler`, now wired in
  `RateLimitSliceTestConfig`.
- **Integration tests never ran under Boot 4** (masked by the broken POM since `a40fbd1`):
  Failsafe put the module's Spring Boot fat jar on the test classpath instead of the unpacked
  `target/classes`, hiding `ca/flowtxt/*.class` from `@SpringBootConfiguration` discovery
  (`Unable to find a @SpringBootConfiguration`) — the failsafe configuration now adds
  `${project.build.outputDirectory}` as an extra classpath element. `TestRestTemplate`
  additionally required `@AutoConfigureTestRestTemplate` on the base test class plus the
  BOM-managed, test-scoped `spring-boot-restclient` module (`RestTemplateBuilder` moved there
  in Boot 4) — both approved additions. Full `./mvnw verify` (unit + Testcontainers ITs +
  JaCoCo check) is green again; README/AGENTS prose corrected from "Boot 3.5" to "Boot 4.1".
- **Optimistic locking was defeated on every message update past the first**: the immutable
  domain `Message` cannot carry JPA's `@Version`, and `JpaMessageRepositoryAdapter` remapped it
  onto a fresh entity per save, resetting the version to 0. The first status write passed by
  luck; any subsequent lifecycle write (e.g. a real Twilio `SENT -> DELIVERED` callback
  sequence) failed with a false concurrent-modification conflict (HTTP 500). The adapter now
  persists load-then-apply: existing rows are loaded as managed entities and updated in place
  (`MessageMapper.apply`, `@MappingTarget`, version explicitly untouched, transactional), fresh
  mapping only for brand-new aggregates. `MessageEntity` regained business-field setters so the
  mapper's update path is not silently generated as a no-op.
- **Integration tests collided on shared PostgreSQL state**: fixed fixtures (e.g. contact phone
  `+5511999999999` created by `SecurityFlowIT` and re-inserted by `JpaRepositoriesIT`) made
  classes fail with duplicate-key errors depending on execution order. The Testcontainers base
  class now truncates all tables before each test, making every `*IT` independent of order.

### Added
- **`scripts/` convention for one-off admin processes** (Twelve-Factor factor 12): a documented
  home for operational tasks sharing the app's env-var contract — an idempotent
  `seed-dev-data.sh` (demo user + contacts through the REST API, duplicate-safe via the new 409),
  a `psql.sh` wrapper for the compose database and the existing `smoke-test.sh` (now builds
  upstream modules in-reactor so it can never boot stale SNAPSHOTs from the local repository).
  All scripts pass shellcheck.
- **Release tagging/rollout convention** (Twelve-Factor factor 5): CI now publishes the
  production image to GHCR on every `main` push — an immutable `sha-<short7>` tag plus a moving
  `edge` tag — and, for annotated `v*` milestone tags, an additional semver image tag plus a
  GitHub Release carrying the versioned jar and the CycloneDX SBOM of the exact shipped image.
  Images were previously built and discarded inside the workflow; nothing was pushed anywhere.
  Convention documented in README "Releases & Rollout" (cut release = annotated tag; rollout =
  pin an immutable tag; rollback = previous immutable tag). Pipeline hardening: actionlint runs
  as the first CI gate (workflow schema, expressions, embedded shellcheck) and `workflow_dispatch`
  enables full-gate rehearsals of any ref without touching main; local validation recipe recorded
  in docs/lessons.md.
- **Fail-fast configuration validation at boot** (Twelve-Factor factor 3): a
  `StartupConfigValidator` runs during context creation — before the web server accepts any
  traffic — and refuses to start with one aggregated, actionable report instead of failing on
  the first request. Always enforced: `jwt.secret` present, free of unresolved `${...}`
  placeholders, and at least 32 bytes (HS256); `jwt.expiration-ms` positive. Enforced outside
  dev (`SPRING_PROFILES_ACTIVE != dev`): the known dev-only placeholder secret is rejected and
  Twilio credentials must be present, placeholder-free, with an E.164 origin number (validated
  through the domain value object). Config is now bound to typed `JwtProperties`/`
  TwilioProperties` records; consumers (`JwtService`, `SmsConfig`, the Twilio signature filter)
  migrated off scattered `@Value` annotations, and `twilio.*` yaml defaults became empty-safe so
  missing env vars can no longer bind the literal `"${VAR}"` string silently.
- **Rate limiting on `/auth/login`**: per-client fixed-window throttling backed by Redis,
  mirroring the spotpobre-api reference design (security filter + typed properties + 3-level
  tests) with two flowtxt adaptations — counters live in Redis (shared across replicas,
  Twelve-Factor factor 6) and rejected requests answer `429 Too Many Requests` with a
  `Retry-After` header. The client key is the first `X-Forwarded-For` hop (else remote address)
  combined with method and path; the counter is incremented atomically by a Lua script
  (`INCR` + conditional `PEXPIRE` + `PTTL`), so keys can never outlive their window
  (coding-standards §6). The limiter fails open with a WARN log when Redis is unavailable
  (availability of login beats best-effort throttling). Configurable via `rate-limit.*`
  properties / `RATE_LIMIT_*` env vars (enabled, limit=20, window=1m, paths=[/auth/login],
  client-ip-header). Covered by `FixedWindowRateLimiterTest`, `RateLimitFilterTest` (unit) and
  `LoginRateLimitIT` (end-to-end against a real Redis container).

### Changed
- **Duplicate contact phone numbers now answer 409 Conflict** instead of leaking a raw 500:
  `RegisterContactUseCase` checks the repository first and raises a state-conflict
  (`IllegalStateException`, mapped by the existing handler) before attempting the insert; the
  previous behaviour surfaced a PostgreSQL unique-constraint violation through the generic error
  path. Covered by new `RegisterContactUseCaseImplTest`.
- **`CacheService.put` now requires a positive TTL** (coding-standards §6): the port signature
  gained a mandatory `java.time.Duration ttl`, making an unbounded key unrepresentable at
  compile time; the Redis adapter rejects null/zero/negative TTLs and writes through
  `set(key, value, ttl)`. Expiry is proven by a unit test and a real-Redis integration test.
  No production callers existed yet — the contract was fixed before first use.
- **`PhoneNumber` now enforces strict ITU-T E.164 in the domain value object**: a leading plus
  is mandatory and the number may carry at most 15 digits with no leading zero in the country
  code (`\+[1-9]\d{1,14}`). Validation lives where the invariant belongs (the record's compact
  constructor, pure Java) instead of an optional-plus regex on the DTO; `ContactRequest` keeps a
  mirrored edge-level pattern. Requests with non-E.164 numbers now fail with 400 — previously
  `"5511999999999"` (no plus) was accepted end to end.
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
