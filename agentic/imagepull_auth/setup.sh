#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="media-processing"
APP="media-processor"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for $APP to exhibit ImagePullBackOff..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 30 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
  if [[ "$STATE" == "ErrImagePull" || "$STATE" == "ImagePullBackOff" ]]; then
    echo "Setup complete: $APP is in ImagePullBackOff state"
    exit 0
  fi
  sleep 4
done

echo "ERROR: $APP did not reach ImagePullBackOff within 120s"
oc get pods -n "$NS" -o wide
exit 1
