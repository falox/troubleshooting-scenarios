#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="rightsizing"
APP="oversized-api"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP deployment to become available..."
oc wait --for=condition=Available "deployment/$APP" -n "$NS" --timeout=120s

echo "Waiting for metrics-server to report usage for $APP..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 24 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if oc adm top pods -l "app=$APP" -n "$NS" --no-headers 2>/dev/null | grep -q .; then
    echo "Setup complete: $APP running with pod metrics available"
    exit 0
  fi
  sleep 5
done
echo "ERROR: pod metrics not available for $APP within 120s"
oc get pods -n "$NS" -o wide
exit 1
