#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="asset-renderer"
APP="renderer-app"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP to exhibit the fault..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || true)
  if echo "$STATE" | grep -Eq "ErrImagePull|ImagePullBackOff"; then
    echo "Setup complete: $APP is in ImagePullBackOff"
    exit 0
  fi
  sleep 5
done
echo "ERROR: $APP did not reach ImagePullBackOff within 120s"
oc get pods -n "$NS" -o wide
exit 1
