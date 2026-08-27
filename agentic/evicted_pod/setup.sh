#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="log-aggregator"
APP="log-collector"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP pod to be evicted (kubelet sweep can take 1-2m)..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 42 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  REASON=$(oc get pods -n "$NS" -l "app=$APP" \
    -o jsonpath='{.items[*].status.reason}' 2>/dev/null || true)
  if echo "$REASON" | grep -q "Evicted"; then
    echo "Setup complete: $APP pod has been evicted"
    exit 0
  fi
  sleep 5
done
echo "ERROR: $APP pod was not evicted within 210s"
oc get pods -n "$NS" -o wide
exit 1
