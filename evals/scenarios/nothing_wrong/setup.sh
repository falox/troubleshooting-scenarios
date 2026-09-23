#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="ticket-service"
APP="ticket-app"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP deployment to become available..."
if ! oc wait --for=condition=Available "deployment/$APP" \
  -n "$NS" --timeout=120s; then
  echo "ERROR: $APP did not become available within 120s"
  oc get pods -n "$NS" -o wide
  exit 1
fi

echo "Waiting for $APP Service to have a ready endpoint..."
for attempt in $(seq 1 30); do
  endpoint_ip=$(oc get endpoints "$APP" -n "$NS" \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)
  if [ -n "$endpoint_ip" ]; then
    echo "Service $APP has ready endpoint $endpoint_ip"
    echo "Setup complete: $APP is Running, Ready, and reachable through its Service"
    exit 0
  fi
  echo "check $attempt/30 — waiting 2s for Service endpoint..."
  sleep 2
done

echo "ERROR: Service $APP did not receive a ready endpoint within 60s"
oc get service "$APP" -n "$NS" -o wide || true
oc get endpoints "$APP" -n "$NS" -o yaml || true
exit 1
