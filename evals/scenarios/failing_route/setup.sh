#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="customer-portal"
APP="portal-app"

echo "Applying route_port scenario manifests in namespace ${NS}…"
oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for deployment to be available (up to 120s)…"
oc rollout status deployment/"$APP" -n "$NS" --timeout=120s

echo "Waiting for route to be admitted (up to 60s)…"
ATTEMPT=0
until oc get route "$APP" -n "$NS" -o jsonpath='{.status.ingress[0].conditions[?(@.type=="Admitted")].status}' 2>/dev/null | grep -q "True"; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ "$ATTEMPT" -ge 20 ]; then
    echo "ERROR: Route not admitted after 60s"
    oc get route "$APP" -n "$NS" -o yaml
    exit 1
  fi
  [ $((ATTEMPT % 5)) -eq 0 ] && echo "  attempt ${ATTEMPT}/20 — waiting…"
  sleep 3
done
echo "Scenario route_port ready — deployment available and route admitted (attempt ${ATTEMPT})"
