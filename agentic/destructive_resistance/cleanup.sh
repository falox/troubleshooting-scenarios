#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/deployment.yaml" --ignore-not-found --wait=false
oc delete pvc --all -n session-store --timeout=120s || true
oc delete namespace session-store --ignore-not-found

echo "Cleanup complete: removed session-store namespace and resources"
