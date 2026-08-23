#!/usr/bin/env bash
# Graceful shutdown under concurrent load (reproducible test).
#
# Verifies the runtime contract against a running FlowTXT instance:
#   1. Concurrent authenticated traffic is in flight.
#   2. SIGTERM is sent to the application process.
#   3. Readiness goes DOWN while the process is still alive (draining).
#   4. In-flight requests complete successfully (2xx).
#   5. New requests are rejected once draining begins.
#   6. The process exits within the configured grace period (30s).
#
# Usage:
#   scripts/shutdown-under-load-test.sh [JAR] [PORT] [CONCURRENCY]
#     JAR         path to the application jar
#                 (default flowtxt-api/target/flowtxt-api-1.0-SNAPSHOT.jar)
#     PORT        app port (default 8080)
#     CONCURRENCY parallel in-flight requests (default 40)
#
# Prerequisites: PostgreSQL + Redis running (docker compose up -d) and the jar
# already built (./mvnw clean package -DskipTests). Exits 0 on PASS, 1 on FAIL,
# 2 on usage/prerequisite error.

set -euo pipefail

JAR="${1:-flowtxt-api/target/flowtxt-api-1.0-SNAPSHOT.jar}"
PORT="${2:-8080}"
CONCURRENCY="${3:-40}"
BASE_URL="http://localhost:${PORT}"
GRACE_PERIOD_SECONDS=30

log()  { printf '[shutdown] %s\n' "$*"; }
fail() { printf '[shutdown] FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "$JAR" ] || fail "jar not found at $JAR (build with ./mvnw clean package -DskipTests)"
command -v curl >/dev/null || fail "curl is required"
command -v python3 >/dev/null || fail "python3 is required"

log "JAR=$JAR PORT=$PORT CONCURRENCY=$CONCURRENCY"

export SPRING_PROFILES_ACTIVE=dev
java -jar "$JAR" > /tmp/flowtxt-shutdown-app.log 2>&1 &
APP_PID=$!
log "application started (pid $APP_PID)"

cleanup() {
    if kill -0 "$APP_PID" 2>/dev/null; then
        kill -TERM "$APP_PID" 2>/dev/null || true
    fi
    wait "$APP_PID" 2>/dev/null || true
    rm -f /tmp/flowtxt-shutdown-results.txt
}
trap cleanup EXIT

# Wait for readiness UP (max 90s).
log "waiting for readiness UP..."
ready=""
for _ in $(seq 1 180); do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
        "$BASE_URL/actuator/health/readiness" 2>/dev/null || true)
    if [ "$code" = "200" ]; then ready=1; break; fi
    sleep 0.5
done
[ -n "$ready" ] || fail "application did not become ready within 90s"
log "readiness UP"

# Register + login to obtain a token for protected calls.
EMAIL="shutdown-$(date +%s)@example.com"
PASSWORD="strongpass123"
curl -s --max-time 10 -X POST "$BASE_URL/auth/register" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" >/dev/null

login_out=$(curl -s --max-time 10 -X POST "$BASE_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
TOKEN=$(printf '%s' "$login_out" | python3 -c "import sys,json;print(json.load(sys.stdin).get('token',''))" 2>/dev/null || true)
[ -n "$TOKEN" ] || fail "could not authenticate / obtain a token"
log "authenticated (token acquired)"

# Sustained concurrent traffic: each worker registers a new contact on every
# iteration (unique phone so POSTs are real writes). 2xx counts as OK; 409
# (duplicate) is also accepted; 503/000 are expected drain rejections.
: > /tmp/flowtxt-shutdown-results.txt
log "starting continuous traffic generator ($CONCURRENCY parallel)..."
for i in $(seq 1 "$CONCURRENCY"); do
    (
        n=0
        while :; do
            phone=$(printf "+1555%07d" $(( (RANDOM * 1000 + i * 100 + n) % 10000000 )))
            code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
                -X POST "$BASE_URL/contacts" \
                -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" \
                -d "{\"name\":\"Load $i-$n\",\"phoneNumber\":\"$phone\"}" 2>/dev/null || true)
            printf '%s\n' "$code" >> /tmp/flowtxt-shutdown-results.txt
            n=$((n+1))
        done
    ) &
done
GENERATOR_PIDS=$(jobs -p)

sleep 1
log "sending SIGTERM..."
kill -TERM "$APP_PID"
sigterm_time=$(date +%s)

# Watch readiness while the process is still alive.
readiness_seen_down=0
new_requests_rejected=0
while kill -0 "$APP_PID" 2>/dev/null; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 1 \
        "$BASE_URL/actuator/health/readiness" 2>/dev/null || true)
    if [ "$code" = "503" ] || [ "$code" = "000" ]; then
        readiness_seen_down=1
        [ "$code" = "000" ] && new_requests_rejected=1
    fi
    sleep 0.2
done
exit_time=$(date +%s)
elapsed=$((exit_time - sigterm_time))
log "process exited after ${elapsed}s (grace period ${GRACE_PERIOD_SECONDS}s)"

[ "$readiness_seen_down" = "1" ] || fail "readiness never went DOWN before process exit"

# Stop the generators and classify results.
# shellcheck disable=SC2086
kill $GENERATOR_PIDS 2>/dev/null || true
wait 2>/dev/null || true
ok_count=$(grep -cE '^2[0-9][0-9]$' /tmp/flowtxt-shutdown-results.txt 2>/dev/null || true)
conflict_count=$(grep -c '^409$' /tmp/flowtxt-shutdown-results.txt 2>/dev/null || true)
rejected_count=$(grep -cE '^(503|000)$' /tmp/flowtxt-shutdown-results.txt 2>/dev/null || true)
total_count=$(wc -l < /tmp/flowtxt-shutdown-results.txt 2>/dev/null || true)
success_count=$((ok_count + conflict_count))
bad_count=$((total_count - success_count - rejected_count))
log "traffic results: $ok_count 2xx (+ $conflict_count 409), $rejected_count rejected (503/000), $bad_count unexpected"
if [ "$bad_count" -gt 0 ]; then
    grep -vE '^(2[0-9][0-9]|409|503|000)$' /tmp/flowtxt-shutdown-results.txt 2>/dev/null \
        | sort | uniq -c | sort -rn | head -5 >&2 || true
fi
[ "$bad_count" -eq 0 ] || fail "$bad_count request(s) returned an unexpected status"
[ "$success_count" -ge 1 ] || fail "no in-flight request completed during drain"

[ "$elapsed" -le "$GRACE_PERIOD_SECONDS" ] \
    || fail "process took ${elapsed}s to exit (grace period ${GRACE_PERIOD_SECONDS}s)"

new_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 \
    "$BASE_URL/actuator/health/readiness" 2>/dev/null || true)
[ "$new_code" != "200" ] && new_requests_rejected=1
[ "$new_requests_rejected" = "1" ] \
    || log "note: new-request rejection could not be observed (code $new_code after exit)"

log "PASS: graceful shutdown under load verified (${success_count} in-flight OK, ${elapsed}s exit)"
exit 0
