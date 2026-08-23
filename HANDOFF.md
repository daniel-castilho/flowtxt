# Handoff — Excellence Plan Implementation (Spotpobre → FlowTXT)

This document hands off a mostly-implemented change set. Read it **in full**
before touching anything. The working branch is `excellence/from-spotpobre`.

---

## 0. Environment note (read first)

This codebase requires **JDK 21** (`spring-boot 4.1`, `source/target=21`).
Before starting, verify in your sandbox:

```bash
java -version          # must say 21
./mvnw -v              # must use JDK 21
curl -sI https://repo.maven.apache.org/maven2/ | head -1   # HTTP/2 200
```

If you only have Java 11 or no Maven Central access, **stop and ask for a new
session** — do not try to work around it.

---

## 1. What this change set does

Ports a set of practices from the reference project `spotpobre` (sibling
directory in the workspace) into FlowTXT. The full plan lives in
`tasks/flowtxt-from-spotpobre-action-plan.md`. The goals:

1. **Typed domain exceptions + canonical error envelope.** Wrong credentials
   return 401 (was 400); unknown aggregates return 404 (was 400); duplicate
   email/phone return 409; validation returns 400 with field map; unexpected
   errors return 500 with a **generic** message (never leak `ex.getMessage()`).
   Every error path — `@RestControllerAdvice`, JWT filter, Twilio signature
   filter, rate-limit filter, authentication entry point, access-denied handler
   — returns the same JSON shape.
2. **Token issuance behind a port.** `JwtService` implements an application
   port `AuthenticationTokenPort`. Register/Authenticate use cases return an
   `AuthResult(user, token)`. `AuthController` no longer depends on an
   infrastructure bean.
3. **Runtime basics.** Graceful shutdown, liveness/readiness probes gated on
   Postgres + Redis (only the probes are public), `application-prod.yaml`,
   Dockerfile base images pinned by digest, structured JSON logs in prod.
4. **Build/test gates.** JaCoCo branch floor (30%) alongside line (40%),
   `check` bound to `verify`. Maven Failsafe runs `*IT` so `./mvnw verify`
   is one complete gate.
5. **Black-box E2E.** `FullWorkflowIT` boots the real servlet container on a
   random port and exercises register → login → contact → message → Twilio
   callback → probes, with **no new test dependency** (`TestRestTemplate`).
6. **Operability.** `docs/release-runbook.md`, `docs/data-model-decisions.md`,
   `deploy/docker-compose.prod.yml`, `scripts/deploy.sh` (health-gated,
   auto-rollback), `scripts/rollback.sh`, `scripts/shutdown-under-load-test.sh`,
   non-blocking `smoke` CI job.

---

## 2. State of the tree (as of handoff)

Commits on `excellence/from-spotpobre`:

- `603a3e9` — the big implementation commit (all the file changes).
- `a40fbd1` — my attempt to fix infra pom dependencies, **which is wrong**
  (see §3). This is the tip of the branch.

There is also an **uncommitted local modification** to
`flowtxt-infrastructure/pom.xml` from a later half-finished fix — discard it
before starting:

```bash
git checkout -- flowtxt-infrastructure/pom.xml
```

**Everything else from `603a3e9` compiles in intent** but has **not been
verified** because the implementing session had no JDK 21 / Maven Central.
You must run `./mvnw verify` and fix whatever actually breaks.

---

## 3. The one known build break (and why it is wrong)

`flowtxt-infrastructure/pom.xml` is currently broken at tip (`a40fbd1`).
The history:

1. Originally the module had no actuator / validation / jackson deps.
2. `GlobalExceptionHandler`, `RestErrorResponseWriter`, and
   `PostgresHealthIndicator` were **moved into infrastructure** from the api
   module, so the module now needs:
   - `org.springframework.boot:spring-boot-starter-actuator` (for
     `Health` / `HealthIndicator`)
   - `org.springframework.boot:spring-boot-starter-validation` (for
     `ConstraintViolationException`)
   - a Jackson `ObjectMapper` on the classpath of the `RestErrorResponseWriter`
3. I guessed at Jackson 3 coordinates three times and was wrong every time:
   - `spring-boot-starter-json` — pulls Jackson 2 (`com.fasterxml.*`), but the
     code uses Jackson 3 (`tools.jackson.*`).
   - `spring-boot-starter-json-3` — does **not exist** in Spring Boot 4.1 GA
     (was a milestone artifact); BOM does not manage it → "version missing".
   - `tools.jackson:jackson-annotations` / `tools.jackson:jackson-databind`
     with no version — the BOM in Boot 4.1 apparently does **not** manage
     those exact coordinates either → "version missing".

**The correct fix is to stop fighting the dependency graph.** Do this:

### Option A (recommended): move the error envelope/writer back to `flowtxt-api`

The error DTO and `RestErrorResponseWriter` are part of the **HTTP contract**.
They belong in `flowtxt-api` (where Spring MVC, Jackson, and validation all
live), not in infrastructure. The security filters/entry point that live in
infrastructure can depend on a small interface defined in infrastructure,
with the implementation supplied by the api module — OR, simpler, have the
filters write the JSON body directly without an ObjectMapper.

Concretely:

- Move `ErrorResponse` and `GlobalExceptionHandler` back under
  `flowtxt-api/src/main/java/ca/flowtxt/api/...` (original layout).
- Keep `RestErrorResponseWriter` in infrastructure but **remove its
  ObjectMapper dependency**: write the JSON string inline with a tiny helper
  (the shape is fixed — `timestamp`, `status`, `error`, `message`, `path`;
  no `validationErrors` in filter rejections). Escape quotes/backslashes in
  the message.
- `RestAuthenticationEntryPoint`, `RestAccessDeniedHandler`,
  `JwtAuthenticationFilter`, `TwilioSignatureValidationFilter`, and
  `RateLimitFilter` already call `errorResponseWriter.write(...)`; that API
  stays, only the implementation changes.
- In `flowtxt-infrastructure/pom.xml`, keep only:
  - `spring-boot-starter-actuator`
  - `spring-boot-starter-validation`

  Remove the `tools.jackson:*` and `spring-boot-actuator*` extras and the
  bogus `spring-boot-starter-json-3`.

### Option B: get the real Jackson 3 coordinates from the working tree

The `flowtxt-api` module already compiles against Jackson 3 —
`SecurityFlowIT` imports `tools.jackson.databind.ObjectMapper` — and
`spring-boot-starter-webmvc` brings it in transitively. Run:

```bash
./mvnw dependency:tree -pl flowtxt-api -Dincludes=tools.jackson,com.fasterxml.jackson
```

Use the **exact** groupId/artifactId/version printed there (with an explicit
`<version>` if it is not BOM-managed for the infra module). This is more
fragile than Option A but keeps files where they are.

**Do not guess a fourth time.** Run `dependency:tree` first.

---

## 4. Files added / changed by the implementation commit (`603a3e9`)

### New files

Domain:
- `flowtxt-domain/src/main/java/ca/flowtxt/domain/common/NotFoundException.java`
- `flowtxt-domain/src/main/java/ca/flowtxt/domain/common/ConflictException.java`
- `flowtxt-domain/src/main/java/ca/flowtxt/domain/common/ForbiddenException.java`
- `flowtxt-domain/src/main/java/ca/flowtxt/domain/common/InvalidCredentialsException.java`

Application:
- `flowtxt-application/.../port/in/AuthResult.java`
- `flowtxt-application/.../port/out/AuthenticationTokenPort.java`

Infrastructure (new locations):
- `flowtxt-infrastructure/.../web/dto/response/ErrorResponse.java`
- `flowtxt-infrastructure/.../web/exception/GlobalExceptionHandler.java`
- `flowtxt-infrastructure/.../security/handler/RestErrorResponseWriter.java`
- `flowtxt-infrastructure/.../security/RestAuthenticationEntryPoint.java`
- `flowtxt-infrastructure/.../security/RestAccessDeniedHandler.java`
- `flowtxt-infrastructure/.../config/PostgresHealthIndicator.java`

API:
- `flowtxt-api/src/test/java/ca/flowtxt/AbstractHttpIntegrationTest.java`
- `flowtxt-api/src/test/java/ca/flowtxt/FullWorkflowIT.java`

Resources:
- `flowtxt-api/src/main/resources/application-prod.yaml`

Deploy/ops:
- `deploy/.env.example`
- `deploy/docker-compose.prod.yml`
- `deploy/README.md`
- `scripts/deploy.sh`
- `scripts/rollback.sh`
- `scripts/shutdown-under-load-test.sh`

Docs:
- `docs/data-model-decisions.md`
- `docs/release-runbook.md`

### Moved (deleted from old location)

- `flowtxt-api/.../api/exception/GlobalExceptionHandler.java` → infra
- `flowtxt-api/.../api/exception/GlobalExceptionHandlerTest.java` → infra
  (`flowtxt-infrastructure/src/test/.../web/exception/`)

### Modified

- Use cases and their tests: `RegisterUserUseCaseImpl`,
  `AuthenticateUserUseCaseImpl`, `RegisterContactUseCaseImpl`,
  `SendMessageUseCaseImpl`, `UpdateMessageStatusUseCaseImpl` and the matching
  tests under `flowtxt-application/src/test/...` — they now throw the typed
  exceptions and (for auth) return `AuthResult`.
- Ports: `AuthenticateUserUseCase`, `RegisterUserUseCase` return `AuthResult`.
- `JwtService` implements `AuthenticationTokenPort`.
- `UseCaseConfig` wires the 3-arg constructors.
- `AuthController` is thin again (no `JwtService` injection).
- `SecurityConfig` uses the new entry point / access denied handler and
  restricts actuator to only the two probes.
- `JwtAuthenticationFilter`, `TwilioSignatureValidationFilter`,
  `RateLimitFilter` use `RestErrorResponseWriter` for JSON rejections.
- `application.yaml`: graceful shutdown, management health groups,
  liveness/readiness probes.
- `pom.xml` (parent): JaCoCo branch floor 0.30, `check` execution in
  `verify`, `<skip.unit.tests>` property.
- `flowtxt-api/pom.xml`: Surefire excludes `*IT.java`; Failsafe plugin runs
  `*IT` in `integration-test`/`verify`.
- Tests updated: `AuthControllerTest`, `RateLimitFilterTest`,
  `TwilioWebhookSecurityTest`, `RateLimitSliceTestConfig`, `SecurityFlowIT`,
  `LoginRateLimitIT`.
- Docs: `README.md`, `AGENTS.md`, `CHANGELOG.md`, `docs/coding-standards.md`,
  `docs/testing-playbook.md`, `docs/twelve-factor.md`.
- `.github/workflows/ci.yml`: Failsafe invocation; new non-blocking `smoke`
  job.
- `Dockerfile`: base images pinned by digest.
- `.gitignore`: ignore `deploy/.env`.

---

## 5. Other likely compile/test failures to check (do not assume they work)

The implementing session could not run Maven. In addition to the pom break,
watch for these on the first `./mvnw verify`:

1. **`MethodArgumentNotValidException` constructor in
   `GlobalExceptionHandlerTest`.** The test uses a real `MethodParameter`
   obtained reflectively from a helper method. Spring Framework 7 may have
   changed constructors. If it does not compile, use
   `new BeanPropertyBindingResult(new Object(), "dto")` +
   `new MethodArgumentNotValidException((MethodParameter) null, br)` only if
   that still compiles; otherwise construct through a mock or use
   `org.springframework.validation.BindException` instead.
2. **`@MockitoBean` package.** The code uses
   `org.springframework.test.context.bean.override.mockito.MockitoBean`
   (Spring Boot 4 / Framework 7 location). If Boot 4.1 moved it again, fix
   the import.
3. **`@WebMvcTest` slice.** `AuthControllerTest` imports
   `SecurityConfig`, `JwtAuthenticationFilter`, `GlobalExceptionHandler`, and
   `RateLimitSliceTestConfig`. Because `GlobalExceptionHandler` moved to
   infrastructure, the slice may not pick it up automatically. If the 401
   assertions fail because no handler is advising the controller, add it to
   `@Import(...)` or move it back to api (Option A in §3).
4. **`RestErrorResponseWriter` in `TwilioSignatureValidationFilter`.** The
   filter previously had a single-arg constructor (`@Value` auth token); it
   now takes `(String authToken, RestErrorResponseWriter writer)` and
   `SecurityConfig.twilioSignatureValidationFilter(...)` supplies both. The
   test (`TwilioWebhookSecurityTest`) constructs it directly with a real
   `ObjectMapper` — under Option A that constructor has to change.
5. **Health group indicator names.** `application.yaml` readiness group is
   `readinessState,postgres,db,redis`. `db` is the auto-configured DataSource
   indicator; `redis` the auto Redis indicator; `postgres` is the custom
   `PostgresHealthIndicator` (named via `@Component("postgres")`). On Boot
   4.1 confirm the auto-configuration actually contributes `db` and `redis`
   (run the app and `curl /actuator/health/readiness`). If names differ,
   fix the group list.
6. **`logging.structured.format.console=ecs` in `application-prod.yaml`.**
   Confirm Spring Boot 4.1 supports the `ecs` value (it may be `logstash` or
   may require a different property path). If it does not, delete those keys
   — structured logging is a nice-to-have, not a correctness issue.
7. **Failsafe `@{argLine}` late-binding.** The Surefire/Failsafe config uses
   `@{argLine}` so the JaCoCo agent set by `prepare-agent` propagates. Check
   the `flowtxt-api/target/site/jacoco/` report after `verify` actually
   contains `*IT` coverage.
8. **`scripts/deploy.sh` / `rollback.sh`.** They use
   `docker compose ... ps --status running` and `sed -i`. Tested with
   `bash -n` only; run them against a disposable stack before trusting.

---

## 6. Definition of Done

From the project's `AGENTS.md` (do not claim Done without all of these):

- [ ] `./mvnw verify` green (unit + Failsafe `*IT`). `*IT` need Docker for
      Testcontainers; if Docker is not available in the sandbox, at least run
      `./mvnw test` and note which ITs were skipped.
- [ ] `./mvnw spotbugs:check` green on all modules.
- [ ] `./mvnw jacoco:check` green (line ≥ 0.40, branch ≥ 0.30 per module).
- [ ] Boundary grep is clean:
      ```bash
      grep -rEn "^import (ca\.flowtxt\.infrastructure|org\.springframework|com\.twilio|io\.jsonwebtoken)" \
        flowtxt-domain/src flowtxt-application/src
      ```
      must print nothing.
- [ ] `bash -n scripts/*.sh` passes.
- [ ] No `JwtService` reference in `flowtxt-api/src/main`.
- [ ] `README.md` Current State / Roadmap, `CHANGELOG.md` Unreleased, and
      `AGENTS.md` Known Technical Debt are consistent with the final code.
- [ ] Do **not** push. The human reviews first.

---

## 7. What NOT to do

- Do **not** add Maven dependencies without first running
  `./mvnw dependency:tree` to confirm the groupId/artifactId/version exists
  and is visible to the module.
- Do **not** add a new JSON library or switch the project back to Jackson 2.
  The app is on Jackson 3 (`tools.jackson.*`).
- Do **not** add `@Transactional` around `SmsService.sendMessage` in
  `SendMessageUseCase` — that is false atomicity across an external system.
  The double-write is documented debt in `docs/data-model-decisions.md`.
- Do **not** introduce new test frameworks (RestAssured, AssertJ, etc.) —
  the plan explicitly used `TestRestTemplate` to avoid new deps.
- Do **not** change the message lifecycle semantics in `Message.java` unless
  a test tells you to.
- Do **not** force-push or push to `main`. Work on `excellence/from-spotpobre`.

---

## 8. Reference material in the workspace

- `tasks/flowtxt-from-spotpobre-action-plan.md` — the original plan, with
  phase-by-phase rationale.
- `spotpobre/` — reference project (Java 21, Spring Boot 3.5). Useful
  patterns for `GlobalExceptionHandler`, `RestErrorResponseWriter`,
  `HealthProbeFlowIT`, `shutdown-under-load-test.sh`. Note it uses Jackson 2
  (`com.fasterxml.*`) and RestAssured, while FlowTXT uses Jackson 3 and no
  RestAssured — translate, don't copy verbatim.
- `docs/lessons.md`, `docs/coding-standards.md`, `AGENTS.md` — project rules.

---

## 9. Suggested first moves

```bash
# 1. clean the half-finished pom edit
git checkout -- flowtxt-infrastructure/pom.xml

# 2. confirm toolchain
java -version
./mvnw -v

# 3. see what jackson the api module actually has
./mvnw dependency:tree -pl flowtxt-api -Dincludes=tools.jackson

# 4. apply Option A from §3 (move error envelope back to api, make the
#    infrastructure writer ObjectMapper-free), then:
./mvnw -pl flowtxt-infrastructure -am compile
./mvnw test
./mvnw verify        # needs Docker for Testcontainers

# 5. fix anything §5 flagged
```

When `./mvnw verify` is green, report back with the test totals and any
deviations from this handoff. Good luck.
