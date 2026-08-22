#!/usr/bin/env bash
# Opens a psql shell against the docker-compose PostgreSQL (or runs a single
# SQL command: ./scripts/psql.sh -c '\dt').
#
# Credentials default to the docker-compose values and follow the same env
# vars the application uses (Twelve-Factor factor 3).
set -euo pipefail

DB_USERNAME="${DB_USERNAME:-flowtxt}"
DB_NAME="${DB_DATABASE:-flowtxt}"

cd "$(dirname "$0")/.."
exec docker compose -f docker/docker-compose.yaml \
  exec -e PGPASSWORD="${DB_PASSWORD:-flowtxt}" postgres \
  psql -U "$DB_USERNAME" -d "$DB_NAME" "$@"
