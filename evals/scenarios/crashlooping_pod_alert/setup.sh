#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../../scripts" && pwd)"
NS="warehouse-ops"
APP="order-fulfillment-daemon"

"$SCRIPT_DIR/enable-uwm.sh"
if oc get namespace "$NS" >/dev/null 2>&1; then
  # Start from the fixture even if an earlier run changed the deployment.
  oc delete deployment "$APP" -n "$NS" --ignore-not-found \
    --cascade=foreground --wait=true --timeout=120s
fi
oc apply -f "$FIXTURE_DIR/deployment.yaml"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

# Wait for the pod to appear
echo "Waiting for $APP pod to be created…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  POD=$(oc get pods -n "$NS" -l "app=$APP" -o name 2>/dev/null | head -1)
  [ -n "$POD" ] && break
  sleep 5
done
[ -n "${POD:-}" ] || { echo "$APP pod never appeared"; oc get pods -n "$NS"; exit 1; }

# Wait for CrashLoopBackOff
echo "Pod exists — waiting for CrashLoopBackOff…"
if ! oc wait --for=jsonpath='{.status.containerStatuses[0].state.waiting.reason}'=CrashLoopBackOff \
  pod -l "app=$APP" -n "$NS" --timeout=300s; then
  echo "Pod did not reach CrashLoopBackOff. Current status:" >&2
  oc get pods -n "$NS" -l "app=$APP" -o wide >&2 || true
  exit 1
fi

echo "Setup complete: $APP is in CrashLoopBackOff state"

"$SCRIPT_DIR/wait-for-alert.sh" "WarehouseOpsPodRestarting" "" 600
