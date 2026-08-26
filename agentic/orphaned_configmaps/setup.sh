#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="deploy-artifacts"
APP="cm-user-app"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP deployment to become available..."
if ! oc wait --for=condition=Available "deployment/$APP" \
  -n "$NS" --timeout=120s; then
  echo "ERROR: deployment $APP did not become available within 120s"
  oc get pods -n "$NS" -o wide
  exit 1
fi

echo "Setup complete: $APP running with orphaned ConfigMaps in namespace"
