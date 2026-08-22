#!/usr/bin/env bash
# Seeds demo data through the running REST API (dev environments only).
#
# Twelve-Factor factor 12: a one-off admin process using the same public
# contract (the REST API) and the same env-var configuration as the app.
#
# Usage:
#   BASE_URL=http://localhost:8080 ./scripts/seed-dev-data.sh
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
SEED_EMAIL="${SEED_EMAIL:-demo@flowtxt.dev}"
SEED_PASSWORD="${SEED_PASSWORD:-strongpass123}"

# name:phone pairs; phones must be E.164 (domain rule).
CONTACTS=(
  "Maria Silva:+5511999999999"
  "John Souza:+5511888888888"
  "Ada Lovelace:+442071838750"
)

post() { # method path body -> http_code (body on stdout)
  curl -sS -o /tmp/flowtxt-seed-last-body -w '%{http_code}' \
    -X "$1" "$BASE_URL$2" -H 'Content-Type: application/json' ${3:+-d "$3"}
}

echo "Seeding FlowTXT dev data at $BASE_URL"

code=$(post POST /auth/register "{\"email\":\"$SEED_EMAIL\",\"password\":\"$SEED_PASSWORD\"}")
if [[ "$code" == "201" ]]; then
  echo "created user $SEED_EMAIL"
elif [[ "$code" == "400" ]]; then
  echo "user $SEED_EMAIL already exists, continuing"
else
  echo "FATAL: register returned HTTP $code:" && cat /tmp/flowtxt-seed-last-body && exit 1
fi

code=$(post POST /auth/login "{\"email\":\"$SEED_EMAIL\",\"password\":\"$SEED_PASSWORD\"}")
[[ "$code" == "200" ]] || {
  echo "FATAL: login returned HTTP $code:" && cat /tmp/flowtxt-seed-last-body && exit 1
}
# The API pretty-prints JSON (INDENT_OUTPUT), so tolerate spaces around ':'.
token=$(sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/flowtxt-seed-last-body)
[[ -n "$token" ]] || { echo "FATAL: no token in login response"; exit 1; }

for pair in "${CONTACTS[@]}"; do
  name="${pair%%:*}"
  phone="${pair#*:}"
  code=$(curl -sS -o /tmp/flowtxt-seed-last-body -w '%{http_code}' \
    -X POST "$BASE_URL/contacts" \
    -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"$name\",\"phoneNumber\":\"$phone\"}")
  if [[ "$code" == "200" || "$code" == "201" ]]; then
    echo "created contact $name ($phone)"
  elif [[ "$code" == "409" ]]; then
    echo "contact $name ($phone) already exists, skipping"
  else
    echo "FATAL: contact $name returned HTTP $code:" \
      && cat /tmp/flowtxt-seed-last-body && exit 1
  fi
done

echo "Seed complete."
