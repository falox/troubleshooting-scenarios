#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/deployment.yaml" --ignore-not-found --wait=false
oc delete configmap app-settings -n feature-service --ignore-not-found
oc delete namespace feature-service --ignore-not-found

echo "Cleanup complete: removed feature-service namespace and resources"
