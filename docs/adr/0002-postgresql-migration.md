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
