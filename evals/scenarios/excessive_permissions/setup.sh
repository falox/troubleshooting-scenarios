#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="fleet-dashboard"
DEPLOY="dashboard-app"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

# Wait for the deployment to become available
echo "Waiting for deployment $DEPLOY to become available…"
oc wait --for=condition=Available deployment/"$DEPLOY" \
  -n "$NS" --timeout=120s

echo "Setup complete: $DEPLOY is running with cluster-admin binding"
