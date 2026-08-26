#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="missing-pvc-test"
APP="missing-pvc-demo"

echo "Applying missing_pvc scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for pod to report unschedulable due to missing PVC (up to 120s)…"
ATTEMPT=0
until oc get events -n "$NS" \
  --field-selector "reason=FailedScheduling" \
  -o jsonpath='{.items[*].message}' 2>/dev/null | grep -q "app-data"; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ "$ATTEMPT" -ge 40 ]; then
    echo "ERROR: FailedScheduling event for missing PVC not found after 120s"
    oc get pods -n "$NS"
    oc get events -n "$NS" --sort-by='.lastTimestamp' | tail -15
    exit 1
  fi
  [ $((ATTEMPT % 10)) -eq 0 ] && echo "  attempt ${ATTEMPT}/40 — waiting…"
  sleep 3
done
echo "Scenario missing_pvc ready — FailedScheduling event confirmed (attempt ${ATTEMPT})"
