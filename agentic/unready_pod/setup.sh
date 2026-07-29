#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"
NS="discovery-hub"
POD_NAME="catalog-index-service"

echo "Applying unready_pod scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

echo "Waiting for readiness probe failure event (up to 60s)…"
FOUND=false
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  EVENTS=$(oc get events -n "$NS" \
    --field-selector "involvedObject.name=$POD_NAME,reason=Unhealthy" \
    -o jsonpath='{.items[*].message}' 2>/dev/null || true)
  if echo "$EVENTS" | grep -q "Readiness probe failed"; then
    echo "Scenario unready_pod ready — readiness probe failure event found (attempt ${ATTEMPT})"
    FOUND=true
    break
  fi
  [ $((ATTEMPT % 10)) -eq 0 ] && echo "  attempt ${ATTEMPT}/60 — waiting…"
  sleep 1
done

if [ "$FOUND" != "true" ]; then
  echo "ERROR: Readiness probe failure not detected within 60s"
  oc describe pod "$POD_NAME" -n "$NS"
  oc get events -n "$NS" --sort-by='.lastTimestamp' | tail -15
  exit 1
fi

"$SCRIPT_DIR/wait-for-alert.sh" "DiscoveryHubPodNotReady"
