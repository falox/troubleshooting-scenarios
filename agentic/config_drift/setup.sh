#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="config-drift"
APP="gateway-proxy"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP deployment to become available..."
oc wait --for=condition=Available "deployment/$APP" -n "$NS" --timeout=120s

echo "Waiting for hot-reload timeline and ECONNREFUSED errors..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 30 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if oc logs -l "app=$APP" -n "$NS" --tail=-1 2>/dev/null | grep -q "config change detected in /config/app.yaml"; then
    break
  fi
  sleep 5
done

ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if oc logs -l "app=$APP" -n "$NS" --tail=20 2>/dev/null | grep -q "ECONNREFUSED"; then
    echo "Setup complete: $APP showing config drift with ECONNREFUSED errors"
    exit 0
  fi
  sleep 5
done
echo "ERROR: $APP did not reach expected state within timeout"
oc get pods -n "$NS" -o wide
exit 1
