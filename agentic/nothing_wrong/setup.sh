#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="nothing-wrong"
APP="healthy-app"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP deployment to become available..."
if ! oc wait --for=condition=Available "deployment/$APP" \
  -n "$NS" --timeout=120s; then
  echo "ERROR: $APP did not become available within 120s"
  oc get pods -n "$NS" -o wide
  exit 1
fi

echo "Setup complete: $APP is Running and Ready"
