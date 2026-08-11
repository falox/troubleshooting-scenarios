#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="limitrange-demo"
DEPLOY="limitrange-demo"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

# Wait for the ReplicaSet to report the LimitRange violation
echo "Waiting for ReplicaSet FailedCreate event…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  MESSAGES=$(oc get events -n "$NS" \
    --field-selector "reason=FailedCreate" \
    -o jsonpath='{.items[*].message}' 2>/dev/null || true)
  if echo "$MESSAGES" | grep -qi "minimum memory usage"; then
    echo "Setup complete: LimitRange violation detected (attempt $ATTEMPT)"
    exit 0
  fi
  sleep 2
done

echo "LimitRange violation event not detected within 120s"
oc get events -n "$NS"
exit 1
