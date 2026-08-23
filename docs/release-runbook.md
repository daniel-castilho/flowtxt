# FlowTXT — Operational Release Runbook

How to operate FlowTXT in production without having written the code: deploy,
roll back, rotate secrets, triage readiness-DOWN and respond to incidents.

**Sources of truth:** `README.md` "Releases & Rollout" (immutable image-tag
convention), `deploy/` (production manifests), `docs/data-model-decisions.md`,
`AGENTS.md`.

Production target: container image from GHCR
(`ghcr.io/daniel-castilho/flowtxt-api`) running behind a proxy/LB, with
managed PostgreSQL and Redis. The app is stateless; deploy by pinning an
**immutable** image tag (`sha-<short7>` for `main`, semver for `v*` releases),
never `:edge` or `:latest`.

---

## 0. Topology and entry points

- All app routes are under `/auth/**`, `/contacts`, `/messages`,
  `/webhook/twilio/**`.
- Public: `POST /auth/register`, `POST /auth/login`.
- Twilio callbacks: `POST /webhook/twilio/status` (protected by the
  `X-Twilio-Signature` HMAC filter, not a bearer token).
- Probes (no auth): `GET /actuator/health/liveness` and
  `GET /actuator/health/readiness`. Every other `/actuator/**` route requires a
  valid bearer token.
- Authenticated routes require `Authorization: Bearer <jwt>`.
- Required config is documented in `.env.example` and enforced at boot by
  `StartupConfigValidator`; production MUST run with
  `SPRING_PROFILES_ACTIVE=prod`.

---

## 1. Deploy a new version

1. CI must have built and scanned the image: the `build` job is green and the
   `image` job completed (non-root check, Trivy HIGH/CRITICAL, SBOM).
2. Pick the immutable tag to deploy:
   - for a `main` rollout: `ghcr.io/daniel-castilho/flowtxt-api:sha-<short7>`;
   - for a milestone: `ghcr.io/daniel-castilho/flowtxt-api:<version>` from the
     annotated `vX.Y.Z` tag.
3. On the production host, change the image reference in
   `deploy/.env`/compose project to the new tag and run
   `scripts/deploy.sh <image-tag>` (or the platform equivalent). The script:
   - pulls the image;
   - recreates the app container(s);
   - polls `GET /actuator/health/readiness` until `200 UP` (bounded deadline);
   - on failure, automatically re-pins/rerolls the previous tag and exits
     non-zero so traffic is never shifted to an unhealthy revision.
4. Post-cutover smoke:
   ```sh
   curl -fsS http://localhost:8080/actuator/health/readiness
   curl -fsS -X POST http://localhost:8080/auth/login \
     -H 'Content-Type: application/json' \
     -d '{"email":"<operator>","password":"<password>"}'
   ```

---

## 2. Roll back

```sh
./scripts/rollback.sh <previous-immutable-tag>
curl -fsS http://localhost:8080/actuator/health/readiness
```

Rollback is safe because every deploy pins an immutable tag: the previous
image is still present and starts identically. State lives in PostgreSQL/Redis,
which the app does not own, so schema changes must be backward-compatible
(Flyway) for one rollback window.

---

## 3. Rotate secrets

All secrets are provided via the environment / secret manager, never baked into
the image. For a rolling rotation:

1. Stage the new value (e.g. `JWT_SECRET="$(openssl rand -base64 48)"`).
2. Restart one instance/fleet with the new value, wait for readiness, verify
   auth still works (old tokens stay valid until their 1h expiry; clients
   re-authenticate transparently).
3. Roll the remaining instances.
4. For Twilio credentials, update the Twilio console and the app env together;
   verify a signed callback is accepted (a bad auth token fails closed with
   403 — see §4).
5. If a secret is suspected compromised, rotate immediately and treat
   outstanding tokens as compromised until expiry.

---

## 4. When readiness is DOWN

Readiness gates on PostgreSQL and Redis (and the Spring readiness state):

```sh
curl -s http://localhost:8080/actuator/health/readiness | jq .
```

1. Identify the failing component (`db`/`postgres` or `redis`) from the
   details (authenticate for full detail if `show-details=when_authorized`).
2. **Postgres DOWN**: check the database host/credentials/network; verify the
   `DATABASE_URL`/`DB_USERNAME`/`DB_PASSWORD` env; check the DB service and
   connection pool (`DB_POOL_MAX_SIZE`). The app does not auto-create schema —
   confirm Flyway ran on boot.
3. **Redis DOWN**: check the Redis host/port/password. The login rate limiter
   fails open (with a WARN log), so an outage does not lock users out, but
   login brute-force protection is degraded until Redis recovers.
4. While a critical dependency is DOWN the LB marks the instance unhealthy and
   stops routing to it; once the dependency recovers, readiness flips to UP
   automatically — no restart required.
5. If all instances are DOWN but dependencies are healthy, inspect logs for a
   `StartupConfigValidator` abort (incomplete `.env`) or an unrecoverable bean
   failure; fix the config and recreate.

---

## 5. Incident response

**Container crash-looping**

```sh
docker logs --tail 200 flowtxt-api
```

- Boot abort mentioning `StartupConfigValidator`: incomplete/incoherent config
  (missing `JWT_SECRET`, Twilio values outside dev, short secret). Fix `.env`,
  recreate.
- `OOMKilled`: check `docker inspect` `State.OOMKilled` and the configured
  memory limit; investigate a leak before raising the limit.

**LB returns 502/504 while the app looks healthy**

- Verify readiness is `200 UP` from the LB's perspective (proxies must see the
  same probe path).
- Check graceful shutdown: on SIGTERM the app drains in-flight requests for up
  to 30s (`server.shutdown=graceful`). A 504 during a deploy that exceeds this
  window indicates requests longer than the grace period.

**Twilio callbacks rejected (403)**

- The signature filter fails closed. Confirm `TWILIO_AUTH_TOKEN` matches the
  Twilio console and the app sees the **public URL** Twilio dialled (proxy
  forwarded headers: `server.forward-headers-strategy=framework` in prod).
- Missing/invalid `X-Twilio-Signature`, or an unconfigured token, all return
  the canonical 403 envelope.

**Messages stuck in PENDING**

- A provider failure should transition the message to `FAILED` (recorded by
  `SendMessageUseCase`). If PENDING persists, inspect the provider error in
  logs and the `messages` table; the double-write design is documented debt in
  `docs/data-model-decisions.md` and will be replaced by an outbox.

**Redis outage (authenticated requests)**

- The rate limiter fails open. If/when user-detail caching is added, it must
  also fail open (degrade to direct Postgres lookup) rather than turning a
  cache outage into an auth outage.

---

## 6. Routine operations

| Task | Command |
| :--- | :--- |
| App logs | `docker logs -f flowtxt-api` |
| Readiness/liveness | `curl -s localhost:8080/actuator/health/readiness` and `/liveness` |
| Database shell | `./scripts/psql.sh` |
| Seed demo data (disposable env only) | `./scripts/seed-dev-data.sh` |
| Graceful-shutdown verification | `scripts/shutdown-under-load-test.sh <jar> <port> <concurrency>` |
| Smoke the whole stack | `./scripts/smoke-test.sh` |
| Host reboot recovery | containers use `restart: unless-stopped`; verify readiness after boot |
| Free disk | `docker system df`; prune build cache with care |

---

## 7. Release checklist

Before cutting an annotated `vX.Y.Z` tag:

- [ ] `./mvnw test` green; `*IT` green; `spotbugs:check` and `jacoco:check`
      green.
- [ ] The change set updated `README.md` (Current State/Roadmap),
      `CHANGELOG.md` and `AGENTS.md` (Known technical debt).
- [ ] `./mvnw clean package` produces the jar; CI built the image, Trivy
      HIGH/CRITICAL clean, SBOM attached.
- [ ] Run the §1 smoke on a disposable environment.
- [ ] Tag only when the human asks; the tag triggers the semver image and
      GitHub Release with the versioned jar + SBOM.
