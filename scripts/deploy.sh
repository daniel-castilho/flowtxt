#!/usr/bin/env bash
# Health-gated deploy for the production compose stack.
#
# Usage: scripts/deploy.sh <immutable-image-tag>
#
# Pulls the pinned image, recreates the app service, and polls the readiness
# probe until UP. If readiness does not come up within the deadline (or the
# container exits), the previous image tag is restored automatically so the
# load balancer never routes to a broken revision.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <immutable-image-tag>" >&2
  exit 2
fi

NEW_TAG="$1"
COMPOSE="docker compose -f deploy/docker-compose.prod.yml"
ENV_FILE="deploy/.env"
READINESS_URL="http://localhost:8080/actuator/health/readiness"
DEADLINE_SECONDS=90

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE (copy from deploy/.env.example)" >&2
  exit 2
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${IMAGE_TAG:?IMAGE_TAG must be set in deploy/.env}"
PREVIOUS_TAG="$IMAGE_TAG"

cd "$(dirname "$0")/.."

echo ">> deploying ${NEW_TAG} (previous: ${PREVIOUS_TAG})"
export IMAGE_TAG="$NEW_TAG"
$COMPOSE pull app
$COMPOSE up -d --no-deps app

echo ">> waiting for readiness (${DEADLINE_SECONDS}s)"
for ((i=0; i<DEADLINE_SECONDS; i++)); do
  if ! $COMPOSE ps --status running app >/dev/null 2>&1; then
    echo "!! app container is not running; rolling back" >&2
    break
  fi
  if curl -fsS "$READINESS_URL" >/dev/null 2>&1; then
    echo ">> readiness UP"
    sed -i.bak "s/^IMAGE_TAG=.*/IMAGE_TAG=${NEW_TAG}/" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
    exit 0
  fi
  sleep 1
done

echo "!! readiness did not pass; rolling back to ${PREVIOUS_TAG}" >&2
export IMAGE_TAG="$PREVIOUS_TAG"
$COMPOSE up -d --no-deps app
for ((i=0; i<DEADLINE_SECONDS; i++)); do
  curl -fsS "$READINESS_URL" >/dev/null 2>&1 && { echo ">> rollback healthy"; exit 1; }
  sleep 1
done
echo "!! rollback also failed; investigate immediately" >&2
exit 1
