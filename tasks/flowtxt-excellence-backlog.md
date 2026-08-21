# FlowTXT — Excellence Backlog

Candidate backlog, ordered by value/risk. Status: **open** unless noted.

| # | Item | Why | Status |
| - | ---- | --- | ------ |
| 1a | Twilio delivery-status webhook endpoint | Close the message lifecycle | **done** (2026-08-21): controller + `UpdateMessageStatusUseCase` + Mongo update shipped |
| 1b | Explicit authorization rule + Twilio request-signature validation for `/webhook/twilio/**` | Make the webhook actually usable and tamper-proof | **done** (2026-08-21): permitAll + fail-closed signature filter |
| 2 | Rate limiting on `/auth/login` (Redis-backed fixed window) | Brute-force protection | open |
| 3 | `PhoneNumber` full E.164 validation in the domain value object | Domain integrity | open |
| 4 | Fail-fast config validation at boot (12-factor factor 3) | Production safety | open |
| 4b | TTL support on `CacheService.put` / Redis adapter (coding-standards §6) | Cache hygiene / unbounded keys risk | open |
| 5 | Raise JaCoCo coverage target | Quality bar | **done** (2026-08-21): 0.10 → 0.40 per module; next step 0.50+ |
| 5b | Purge Lombok from persistence documents (records) and drop the dependency (Phase C) | Consistency with the rich immutable domain | **done** (2026-08-21): zero Lombok in sources or POMs |
| 6 | Release tagging/rollout convention (image + jar per commit) | Operability | open |
| 7 | `scripts/` for admin/one-off operations (e.g. seed data) | Operability | open |
