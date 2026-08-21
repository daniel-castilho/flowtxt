# Testing Playbook

**Role:** Write and interpret tests for this Java 21 multi-module Clean Architecture service
(Spring Boot 3.5, MongoDB, Redis, Twilio).
**Stack constraints:** JUnit 5 + Mockito for unit tests; Testcontainers (MongoDB, Redis) for
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
5. **Integration (`*IT`, Testcontainers)** — the full application against real MongoDB + Redis
   containers: repository adapters (`MongoRepositoriesIT`), the cache adapter
   (`RedisCacheAdapterIT`) and the end-to-end security flow (`SecurityFlowIT`:
   register → login → protected endpoint with/without token). Skipped automatically when Docker
   is unavailable.

Never point tests at a shared local Mongo/Redis — always containers (or mocks).

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
public abstract class AbstractIntegrationTest { /* Mongo + Redis containers + @DynamicPropertySource */ }
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
| | `api/MongoRepositoriesIT` | Contact/User/Message persistence |
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
| **Stack** | Java 21, Spring Boot 4.1.x, Mongo 7, Redis 7 — no version drift |

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
| **Flaky / env** | Port, Redis, Mongo | Re-run; fix the cause — don't skip tests |

**Priority when many fail:** compile/annotation → domain → application → infrastructure → API →
integration.

---

## Do not

- Skip, delete, or `@Disabled` tests to green the build
- Add new test frameworks without human approval
- Point tests at a shared local Mongo/Redis instance
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
