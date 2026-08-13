#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="credential-store"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for CreateContainerConfigError on missing-secret-key-demo..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATUS=$(oc get pods -n "$NS" -l app=missing-secret-key-demo \
    -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
  if [ "$STATUS" = "CreateContainerConfigError" ]; then
    echo "Setup complete: CreateContainerConfigError detected (attempt $ATTEMPT)"
    exit 0
  fi
  sleep 1
done

echo "WARNING: CreateContainerConfigError not detected within 60s"
oc get pods -n "$NS" -l app=missing-secret-key-demo
oc get events -n "$NS" --sort-by='.lastTimestamp' | tail -5
exit 1
