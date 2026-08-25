#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="wrong-probe-port"
APP="probe-port-demo"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP to exhibit the fault..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 36 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || true)
  if echo "$STATE" | grep -q "CrashLoopBackOff"; then
    echo "Setup complete: $APP is in CrashLoopBackOff"
    exit 0
  fi
  sleep 5
done
echo "ERROR: $APP did not reach CrashLoopBackOff within 180s"
oc get pods -n "$NS" -o wide
exit 1
