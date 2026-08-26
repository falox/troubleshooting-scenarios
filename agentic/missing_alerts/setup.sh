#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"
NS="missing-alerts"
APP="payments-api"

"$SCRIPT_DIR/enable-uwm.sh"
oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP deployment to become available..."
if ! oc wait --for=condition=Available "deployment/$APP" \
  -n "$NS" --timeout=120s; then
  echo "ERROR: deployment $APP did not become available within 120s"
  oc get pods -n "$NS" -o wide
  exit 1
fi

echo "Setup complete: $APP running with recording-rule-only PrometheusRule"
