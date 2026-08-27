#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="platform-services"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for all deployments to become available..."
for deploy in web-frontend batch-worker legacy-api billing-api; do
  oc wait --for=condition=Available "deployment/$deploy" -n "$NS" --timeout=150s
done

echo "Setup complete: all platform-services workloads running"
