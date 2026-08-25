#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="legacy-migration"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for SCC rejection FailedCreate event on scc-demo..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  EVENTS=$(oc get events -n "$NS" \
    --field-selector "reason=FailedCreate" \
    -o jsonpath='{.items[*].message}' 2>/dev/null || true)
  if echo "$EVENTS" | grep -qi "security context constraint"; then
    echo "Setup complete: SCC rejection detected (attempt $ATTEMPT)"
    exit 0
  fi
  sleep 1
done

echo "WARNING: SCC rejection event not detected within 60s"
oc get events -n "$NS" --sort-by='.lastTimestamp' | tail -10
exit 1
