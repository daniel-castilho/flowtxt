# Lessons — FlowTXT

Durable engineering rules learned the hard way in this project. Each entry states the failure
mode and the rule that prevents it. Add a new entry only when a rule proves itself; keep entries
short and actionable.

---

## Always verify the repository's default branch before writing CI workflows (2026-08-21)

The `flappy-bird` repo used `main`, and workflows written with `branches: [master]` never
triggered — zero runs after a push. The same check now runs before any workflow lands here:
`git symbolic-ref --short refs/remotes/origin/HEAD`.

**Rule:** before creating/updating CI workflows, detect the default branch and match it.

---

## Maven multi-module: know where a dependency block lands (2026-08-21)

While adding Testcontainers to `flowtxt-api/pom.xml`, a naive string replace inserted the
dependencies inside `<dependencyManagement>` (the first `</dependencies>` in the file) instead
of the real `<dependencies>` block — the classes were "managed" but never on the test classpath
(`cannot find symbol: GenericContainer`). Also, `org.testcontainers` versions were not managed
by the Spring Boot BOM in this setup, so explicit `<version>` was required.

**Rule:** when editing a POM with a `<dependencyManagement>` section, insert test/runtime
dependencies into the actual `<dependencies>` block (after `</dependencyManagement>`), and give
unmanaged coordinates an explicit version.

---

## `@WebMvcTest` applies Spring Security defaults — load the real SecurityConfig (2026-08-21)

Controller slice tests initially failed with 403 (CSRF) then 401 (default auth) because
`@WebMvcTest` boots Spring Security's defaults when `spring-security` is on the classpath, and
`addFilters = false` alone did not make the endpoints reachable.

**Rule:** for controller tests of a secured app, `@Import` the real `SecurityConfig` + the JWT
filter, `@MockBean` the security collaborators (JwtService, UserDetailsService), and add
`with(csrf())` to mutating requests. The real authorization behaviour is then exercised in
slice tests too, not only in `*IT`.

---

## `-Dtest='*IT'` fails on modules without ITs — set failIfNoSpecifiedTests=false (2026-08-21)

Running the integration pattern across all modules aborted on `flowtxt-domain` with
`No tests matching pattern "*IT" were executed`.

**Rule:** use `-Dtest='*IT' -Dsurefire.failIfNoSpecifiedTests=false` when the pattern applies to
a multi-module reactor.

---

## Testcontainers `disabledWithoutDocker = true` makes ITs portable (2026-08-21)

Integration tests (`*IT`) boot real PostgreSQL + Redis containers. On machines without Docker they
are **skipped** (not failed), and in CI (which has Docker) they run for real.

**Rule:** annotate integration base classes with
`@Testcontainers(disabledWithoutDocker = true)` so the suite is CI-strict but developer-friendly.

---

## A host service can mask wrong test configuration — hermeticity is proven only in CI (2026-08-21)

The Redis integration test passed for weeks on dev machines while connecting to
`localhost:6379` — an unrelated local Redis container from another project answered every call.
The dynamic Testcontainers properties were registered under the pre-Spring-Boot-3
`spring.redis.*` prefix, which Boot 3 ignores, so the mapped container port was never applied.
CI's hermetic runner had no such service and went red on day one of actually running ITs.

**Rule:** after changing connection configuration, verify which address the client ACTUALLY
dials (log it once) instead of trusting a green local run; treat any pass that could be served
by an unrelated host service as unproven.

---

## Research a precise failure signature before debugging by trial and error (2026-08-21)

The integration failures had a crisp, searchable signature
(`ObjectOptimisticLockingFailureException` + `@Version` + assigned id). A web search over that
signature surfaced the exact mechanism in minutes (Spring Data state detection, Hibernate's
strict merge) plus the accepted fix pattern — no speculative code changes were needed at any
point. Guess-first would have burned a fix-run cycle on each wrong hypothesis.

**Rule:** when a failure has a precise exception/symptom signature, search the web first
(Spring Data issues, Hibernate discourse, Stack Overflow), confirm the mechanism against our
own code/generated artifacts, and only then implement.

---

## Immutable aggregates must be persisted load-then-apply, never blind-remapped (2026-08-21)

The immutable domain `Message` cannot carry JPA bookkeeping fields. Mapping it onto a FRESH
entity on every save reset `@Version` to 0: the first update passed by luck (version matched)
and any subsequent write died with a false "Row was already updated or deleted by another
transaction". This broke real Twilio callback sequences (`SENT -> DELIVERED`), not just tests.
Compounding trap: MapStruct silently generated a no-op for `@MappingTarget` because the entity
had lost its setters in the Lombok purge — check generated sources when mapper behaviour looks
inert.

**Rule:** adapters persisting versioned entities load the managed row first and apply state via
an explicit update method (`@MappingTarget`, version explicitly ignored); fresh mapping happens
only for brand-new aggregates. Never let a mapper rebuild a versioned entity from scratch on an
update path.

---

## Validate GitHub Actions workflows in three local layers before burning a runner (2026-08-21)

Workflow YAML is not executable locally: registry auth (`GITHUB_TOKEN`), GHCR, the Releases API
and event variables only exist inside GitHub. But "can't run locally" does not mean "can't be
verified locally" — three layers cover almost everything:

1. **actionlint** (official Docker image `rhysd/actionlint:latest`, stdin-friendly) — schema,
   `${{ }}` expressions and embedded shellcheck of `run:` blocks; also wired as the first CI
   gate so regressions die cheaply.
2. **Extracted `run:` scripts with mocked env** — copy the block verbatim into a bash script,
   feed fake `GITHUB_SHA`/`GITHUB_REF`/`GITHUB_OUTPUT`, assert outputs for each trajectory.
   Caveat learned twice: runners use bash; local shells may be zsh — run the simulation through
   explicit `bash`.
3. **`workflow_dispatch` trigger** — full-gate rehearsal of any ref on a real runner without
   touching `main`; publish steps stay event-gated and skipped.

Residual platform-only risk stays explicitly bounded: first package push to GHCR (repo/org
package settings), `gh release create`, artifact layout assumptions — contained by ordering
(push after gates, release after image), so failure is visible with no bad artifact shipped.

**Rule:** before pushing workflow changes, run actionlint + simulate every new `run:` block per
trajectory; rehearse on `workflow_dispatch`; state precisely which risks only a real event can
retire.
