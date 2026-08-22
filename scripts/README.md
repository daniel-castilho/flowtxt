# scripts/ — One-off admin & operational processes

Twelve-Factor factor 12: admin/maintenance work runs as **one-off processes**
in the same environment as the app — same codebase, same env-var config, same
backing services. Anything you would otherwise do by hand on a server belongs
here instead.

## Conventions

| Rule | Why |
| :--- | :--- |
| Bash with `set -euo pipefail`, executable bit set | Fail fast on typos and unset vars |
| Config from environment variables with dev-only defaults | Same contract as the app itself (factor 3); never hardcode secrets |
| Idempotent when feasible | Re-running a seed or fix-up must not corrupt state |
| Must pass shellcheck before commit | Same static bar the workflows have |
| No secrets in output/logs | Mirrors coding-standards §5 |

Run everything from the repository root:

```sh
./scripts/<name>.sh
```

## Inventory

| Script | Purpose |
| :--- | :--- |
| `seed-dev-data.sh` | Seeds a demo user + contacts through the running REST API (idempotent) |
| `smoke-test.sh` | Boots the stack and exercises health -> register -> login -> protected flow |
| `psql.sh` | Opens a `psql` shell against the docker-compose PostgreSQL |

Flyway owns schema changes (`V2__*.sql` migrations) — do not add DDL scripts
here.
