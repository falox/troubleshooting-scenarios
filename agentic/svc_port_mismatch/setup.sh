#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="svc-port-demo"

echo "Applying svc_port_mismatch scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for svc-port-demo deployment to be ready…"
oc wait --for=condition=available deployment/svc-port-demo -n "$NS" --timeout=120s

echo "Waiting for svc-port-svc endpoints (selector is correct, port is not)…"
ATTEMPT=0
until [ "$ATTEMPT" -ge 20 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  EP_COUNT=$(oc get endpoints svc-port-svc -n "$NS" -o jsonpath='{.subsets[*].addresses}' 2>/dev/null | grep -c "ip" || true)
  if [ "$EP_COUNT" -gt 0 ]; then
    echo "Scenario svc_port_mismatch ready — endpoints populated (attempt ${ATTEMPT})"
    exit 0
  fi
  echo "  attempt ${ATTEMPT}/20 — waiting 3s…"
  sleep 3
done

echo "ERROR: Endpoints for svc-port-svc not populated within 60s"
oc get endpoints svc-port-svc -n "$NS" -o yaml 2>/dev/null || true
exit 1
