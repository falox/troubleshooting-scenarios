#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/deployment.yaml" --ignore-not-found --wait=false
oc delete configmap app-settings -n missing-configmap --ignore-not-found
oc delete namespace missing-configmap --ignore-not-found

echo "Cleanup complete: removed missing-configmap namespace and resources"
