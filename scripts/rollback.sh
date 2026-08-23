#!/usr/bin/env bash
# Instant rollback to a previously deployed immutable image tag.
#
# Usage: scripts/rollback.sh <immutable-image-tag>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <immutable-image-tag>" >&2
  exit 2
fi

TARGET_TAG="$1"
COMPOSE="docker compose -f deploy/docker-compose.prod.yml"
ENV_FILE="deploy/.env"
READINESS_URL="http://localhost:8080/actuator/health/readiness"
DEADLINE_SECONDS=90

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE (copy from deploy/.env.example)" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

echo ">> rolling back to ${TARGET_TAG}"
export IMAGE_TAG="$TARGET_TAG"
$COMPOSE up -d --no-deps app

for ((i=0; i<DEADLINE_SECONDS; i++)); do
  if curl -fsS "$READINESS_URL" >/dev/null 2>&1; then
    echo ">> rollback healthy"
    sed -i.bak "s/^IMAGE_TAG=.*/IMAGE_TAG=${TARGET_TAG}/" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
    exit 0
  fi
  sleep 1
done

echo "!! rollback target did not become ready; investigate immediately" >&2
exit 1
