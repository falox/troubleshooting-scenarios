#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="multi-issue-app"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for CreateContainerConfigError on double-fault-demo..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATUS=$(oc get pods -n "$NS" -l app=double-fault-demo \
    -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
  if [ "$STATUS" = "CreateContainerConfigError" ]; then
    echo "Setup complete: CreateContainerConfigError detected (attempt $ATTEMPT)"
    exit 0
  fi
  sleep 1
done

echo "WARNING: CreateContainerConfigError not detected within 60s"
oc get pods -n "$NS" -l app=double-fault-demo
oc get events -n "$NS" --sort-by='.lastTimestamp' | tail -5
