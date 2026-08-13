#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="ha-services"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for FailedScheduling events on antiaffinity-demo pods..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 90 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  REASONS=$(oc get events -n "$NS" \
    --field-selector "reason=FailedScheduling" \
    -o jsonpath='{.items[*].reason}' 2>/dev/null || true)
  if echo "$REASONS" | grep -q "FailedScheduling"; then
    echo "Setup complete: FailedScheduling event detected (attempt $ATTEMPT)"
    exit 0
  fi
  sleep 1
done

echo "WARNING: FailedScheduling event not detected within 90s"
oc get pods -n "$NS" -l app=antiaffinity-demo
oc get events -n "$NS" --sort-by='.lastTimestamp' | tail -10
