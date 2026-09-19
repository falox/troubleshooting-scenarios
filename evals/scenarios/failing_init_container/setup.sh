#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="onboarding-app"
APP="onboarding-worker"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP init container to fail..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[*].status.initContainerStatuses[*].state.waiting.reason}' 2>/dev/null || true)
  TERM=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[*].status.initContainerStatuses[*].state.terminated.reason}' 2>/dev/null || true)
  LAST=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[*].status.initContainerStatuses[*].lastState.terminated.reason}' 2>/dev/null || true)
  if echo "$STATE $TERM $LAST" | grep -Eq "CrashLoopBackOff|Error"; then
    echo "Setup complete: $APP init container is failing"
    exit 0
  fi
  sleep 5
done
echo "ERROR: $APP init container did not reach the expected fault state within 120s"
oc get pods -n "$NS" -o wide
exit 1
