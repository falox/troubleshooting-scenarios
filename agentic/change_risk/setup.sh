#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="change-risk"
APP="orders-api"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP deployment to become available..."
oc wait --for=condition=Available "deployment/$APP" -n "$NS" --timeout=120s

echo "Setup complete: $APP running with proposed-change ConfigMap deployed"
