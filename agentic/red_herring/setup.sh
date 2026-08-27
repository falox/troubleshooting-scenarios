#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="payment-gateway"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for gateway-app to exhibit the fault..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=gateway-app" \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}{" "}{.items[*].status.containerStatuses[*].lastState.terminated.reason}' 2>/dev/null || true)
  if echo "$STATE" | grep -Eq "CrashLoopBackOff|Error"; then
    break
  fi
  sleep 5
done
if ! echo "$STATE" | grep -Eq "CrashLoopBackOff|Error"; then
  echo "ERROR: gateway-app did not reach expected fault state within 120s"
  oc get pods -n "$NS" -o wide
  exit 1
fi

echo "Waiting for gateway-monitor to be Running but not Ready..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  PHASE_READY=$(oc get pods -n "$NS" -l "app=gateway-monitor" \
    -o jsonpath='{.items[0].status.phase}/{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
  if [ "$PHASE_READY" = "Running/false" ]; then
    echo "Setup complete: gateway-app is crash-looping, gateway-monitor is Running but not Ready"
    exit 0
  fi
  sleep 5
done
echo "ERROR: expected state not reached within 120s"
oc get pods -n "$NS" -o wide
exit 1
