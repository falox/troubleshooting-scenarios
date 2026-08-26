#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="bad-command"
APP="bad-command-demo"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP to exhibit the fault..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || true)
  if echo "$STATE" | grep -Eq "StartError|CreateContainerError|CrashLoopBackOff"; then
    echo "Setup complete: $APP is crash-looping"
    exit 0
  fi
  sleep 5
done
echo "ERROR: $APP did not reach the expected fault state within 120s"
oc get pods -n "$NS" -o wide
exit 1
