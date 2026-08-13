#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="svc-selector-test"
APP="svc-selector-demo"
SVC="svc-selector-svc"

echo "Applying svc_selector scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for deployment to be available (up to 120s)…"
oc rollout status deployment/"$APP" -n "$NS" --timeout=120s

echo "Confirming service has zero endpoints…"
EP_COUNT=$(oc get endpoints "$SVC" -n "$NS" -o jsonpath='{.subsets[*].addresses}' 2>/dev/null | wc -c)
if [ "$EP_COUNT" -gt 2 ]; then
  echo "ERROR: Service $SVC unexpectedly has endpoints"
  oc get endpoints "$SVC" -n "$NS" -o yaml
  exit 1
fi
echo "Scenario svc_selector ready — deployment available, service has zero endpoints"
