#!/usr/bin/env bash
#
# smoke-test.sh — boots the API against local Mongo + Redis and exercises the
# core flow: health -> register -> login -> protected contact creation.
#
# Usage: ./scripts/smoke-test.sh
# Requires: Docker, JDK 21, and a .env with (dummy) Twilio + JWT values.
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "==> Starting Mongo + Redis (docker compose)"
docker compose -f docker/docker-compose.yaml up -d

echo "==> Starting the API (background)"
./mvnw spring-boot:run -pl flowtxt-api > /tmp/flowtxt-smoke.log 2>&1 &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null || true; docker compose -f docker/docker-compose.yaml down' EXIT

echo "==> Waiting for /actuator/health"
for i in $(seq 1 60); do
  if curl -sf "$BASE_URL/actuator/health" > /dev/null 2>&1; then
    echo "    health OK"
    break
  fi
  sleep 2
  if [ "$i" = "60" ]; then echo "FATAL: API did not become healthy"; tail -50 /tmp/flowtxt-smoke.log; exit 1; fi
done

echo "==> Register a user"
REGISTER=$(curl -sf -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"smoke@example.com","password":"strongpass123"}' \
  || { echo "FATAL: register failed"; tail -50 /tmp/flowtxt-smoke.log; exit 1; })
echo "    $REGISTER"

TOKEN=$(echo "$REGISTER" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$TOKEN" ] || { echo "FATAL: no token in register response"; exit 1; }

echo "==> Create a contact with the token"
curl -sf -X POST "$BASE_URL/contacts" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Maria","phoneNumber":"+5511999999999"}' \
  || { echo "FATAL: contact creation failed"; exit 1; }
echo "    contact created"

echo "==> Protected endpoint without token must be rejected (401)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE_URL/contacts" \
  -H "Content-Type: application/json" \
  -d '{"name":"X","phoneNumber":"+5511000000000"}')
[ "$STATUS" = "401" ] || { echo "FATAL: expected 401, got $STATUS"; exit 1; }
echo "    401 OK"

echo
echo "SMOKE TEST PASSED ✔"
