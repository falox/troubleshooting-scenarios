#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="cascading-failure"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for cascade-backend to exhibit ImagePullBackOff..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=cascade-backend" \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || true)
  if echo "$STATE" | grep -Eq "ErrImagePull|ImagePullBackOff"; then
    echo "Backend is in ImagePullBackOff"
    break
  fi
  sleep 5
done

echo "Waiting for cascade-frontend to be Running but not Ready..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  PHASE_READY=$(oc get pods -n "$NS" -l "app=cascade-frontend" \
    -o jsonpath='{.items[0].status.phase}/{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
  if [ "$PHASE_READY" = "Running/false" ]; then
    echo "Setup complete: frontend Running but not Ready, backend in ImagePullBackOff"
    exit 0
  fi
  sleep 5
done
echo "ERROR: cascading_failure setup did not reach expected state within 120s"
oc get pods -n "$NS" -o wide
exit 1
