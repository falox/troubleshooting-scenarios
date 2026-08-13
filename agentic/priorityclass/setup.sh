#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="priorityclass-test"
APP="priorityclass-demo"

echo "Applying priorityclass scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Confirming no pods are created due to missing PriorityClass (up to 60s)…"
ATTEMPT=0
until oc get events -n "$NS" \
  --field-selector "reason=FailedCreate" \
  -o jsonpath='{.items[*].message}' 2>/dev/null | grep -q "eval-critical-priority"; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ "$ATTEMPT" -ge 20 ]; then
    echo "ERROR: FailedCreate event for missing PriorityClass not found after 60s"
    oc get pods -n "$NS"
    oc get events -n "$NS" --sort-by='.lastTimestamp' | tail -15
    exit 1
  fi
  [ $((ATTEMPT % 5)) -eq 0 ] && echo "  attempt ${ATTEMPT}/20 — waiting…"
  sleep 3
done
echo "Scenario priorityclass ready — FailedCreate event confirmed (attempt ${ATTEMPT})"
