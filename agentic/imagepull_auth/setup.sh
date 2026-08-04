#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="imagepull-auth"
APP="imagepull-auth-app"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for $APP to exhibit ImagePullBackOff..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 30 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
  if [[ "$STATE" == "ErrImagePull" || "$STATE" == "ImagePullBackOff" ]]; then
    break
  fi
  sleep 4
done

echo "Setup complete: $APP is in ImagePullBackOff state"
