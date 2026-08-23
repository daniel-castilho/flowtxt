# Data Model Decisions

Record of the single-source-of-truth decisions behind FlowTXT's persistence
and consistency model. Keep this file in sync whenever the data model changes.
The persistence adapter is JPA/PostgreSQL; Flyway owns the schema under
`flowtxt-api/src/main/resources/db/migration`.

## User

- **Source of truth:** the `users` table, keyed by `id` (UUID). Email is a
  natural key with a uniqueness constraint and is stored lower-cased/trimmed.
- Registration is an insert; duplicate emails are rejected at the application
  layer (`RegisterUserUseCase` → `ConflictException`, HTTP 409) and additionally
  guarded by the unique index so a race cannot create two rows.
- Passwords are stored only as a BCrypt hash behind the domain
  `PasswordHasher` port. The application layer never sees the hashing library.

## Contact

- **Source of truth:** the `contacts` table, keyed by `id` (UUID). The E.164
  phone number is a natural key with a uniqueness constraint.
- The `PhoneNumber` value object enforces strict E.164
  (`+[1-9]\d{1,14}`) in the domain; the DTO mirrors the rule at the edge with
  a Bean Validation pattern. Invalid numbers fail fast with 400.
- Registering a duplicate phone number returns `ConflictException` (409),
  never a raw 500 from the unique-index violation.

## Message lifecycle (PENDING → SENT/FAILED → DELIVERED/...)

- **Source of truth:** the `messages` table, keyed by `id` (UUID) with a unique
  `sid` column populated once the provider accepts the message.
- The forward-only status lifecycle is enforced in the domain entity
  (`Message`), not in services or controllers. Replaying the same status is an
  idempotent no-op; invalid backward/sideways jumps raise
  `IllegalStateException`, which the API edge maps to HTTP 409. Unknown
  provider statuses are mapped to `MessageStatus.UNKNOWN` at the boundary and
  accepted from any state so odd callbacks never break the flow.
- **Double write PENDING → SENT/FAILED is intentional:** `SendMessageUseCase`
  first persists a `PENDING` audit trail, then calls the SMS provider, then
  persists the outcome. A provider failure records `FAILED` instead of leaving
  the message stuck. This is accepted technical debt; the proper fix is a
  transactional outbox so the provider call and state transition become
  atomic/retryable. `@Transactional` across the provider call must not be
  reintroduced — it gives false atomicity across an external system.

## Optimistic locking (@Version) and immutable-domain persistence

- `MessageEntity` carries a JPA `@Version`. The domain `Message` is immutable
  and cannot carry the version field, so the adapter must **load-then-apply**:
  rehydrate the managed entity, apply the domain transition through
  `MessageMapper` (with `@MappingTarget` and the version explicitly untouched),
  and let JPA flush the update. Re-mapping a fresh entity per save would reset
  the version to 0 and cause a false concurrent-modification conflict on every
  lifecycle write past the first.
- The same load-then-apply pattern is the template for any other aggregate
  whose persistence model needs optimistic locking while the domain stays
  immutable.

## Twilio status callbacks

- Callbacks arrive at `POST /webhook/twilio/status`. The route is `permitAll`
  in `SecurityConfig` (callbacks carry no bearer token); authenticity is
  enforced by `TwilioSignatureValidationFilter`, which fails closed with HTTP
  403 when the `X-Twilio-Signature` header is missing/invalid or the auth
  token is unconfigured.
- The signature is computed over the full public request URL (scheme, host,
  path, query) plus sorted POST parameters, HMAC-SHA1 with the account auth
  token, constant-time compared. Behind a proxy the application must see the
  same public URL Twilio dialled.

## Redis

- Used for two concerns: the `CacheService` port (cache) and the login rate
  limiter (shared fixed window, atomic Lua `INCR`/`PEXPIRE`/`PTTL`).
- All cache writes carry a **mandatory positive TTL** (port signature makes an
  unbounded key unrepresentable); keys follow `flowtxt:<purpose>:<id>`. Never
  store secrets or large blobs.
- The rate limiter **fails open** with a WARN log when Redis is unavailable so
  an outage never locks every user out. If/when authentication results are
  cached in Redis, they must degrade the same way (fall back to direct
  PostgreSQL lookup) rather than turning a cache outage into an auth outage.
