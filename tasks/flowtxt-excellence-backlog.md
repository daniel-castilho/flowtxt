# FlowTXT — Excellence Backlog

Candidate backlog, ordered by value/risk. Status: **open** unless noted.

| # | Item | Why | Status |
| - | ---- | --- | ------ |
| 1 | Twilio delivery-status webhook endpoint (`SmsService.receiveMessage` stub → real endpoint + DTO wiring) | Close the message lifecycle | open |
| 2 | Rate limiting on `/auth/login` (Redis-backed fixed window) | Brute-force protection | open |
| 3 | `PhoneNumber` full E.164 validation in the domain value object | Domain integrity | open |
| 4 | Fail-fast config validation at boot (12-factor factor 3) | Production safety | open |
| 5 | Raise JaCoCo coverage target (0.10 → 0.50+) as tests expand | Quality bar | open |
| 6 | Release tagging/rollout convention (image + jar per commit) | Operability | open |
| 7 | `scripts/` for admin/one-off operations (e.g. seed data) | Operability | open |
