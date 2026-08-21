# FlowTXT — AI Engineer Prompt (template)

Use this template for any AI-assisted task on this repository.

## Sources of truth (read in order, before starting)

1. `AGENTS.md` — project rules (non-negotiable; follow it)
2. `README.md` — overview, Current State, Roadmap
3. `docs/coding-standards.md` — day-to-day coding detail
4. `docs/testing-playbook.md` — how to test
5. `docs/lessons.md` — hard-won rules
6. `docs/adr/*` — architecture decisions
7. `tasks/flowtxt-excellence-backlog.md` — pending work

## Non-negotiable rules

1. **English only** for code, comments, commits, docs and logs.
2. Obey the boundary rules: `domain/` and `application/` never import `infrastructure` or
   framework code (verify with the grep in AGENTS.md rule 1).
3. No new Maven dependency without explicit human approval.
4. Every new endpoint declares an explicit authorization rule in `SecurityConfig`.
5. Tests: `./mvnw test` must stay green; extend the existing suite; `*IT` for container-backed
   behaviour.
6. Doc sync is part of Done: update README "Current State", CHANGELOG and AGENTS "Known
   technical debt" in the same change set.
7. Do not push to the remote unless the human explicitly asks.

## How to work

1. Baseline: `git status`, `git log --oneline -5`, `./mvnw test`.
2. Implement the smallest focused change; one concern per commit.
3. After code: `./mvnw test` (+ `./mvnw jacoco:check`, `./mvnw spotbugs:check` as appropriate).
4. Update the backlog/status files touched.

## Done report (mandatory)

```markdown
## Summary
## Implemented
## Tests added/updated
## Quality gates
## Residual risks / follow-ups
## Docs touched
```
