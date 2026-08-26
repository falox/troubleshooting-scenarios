#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/deployment.yaml" --ignore-not-found --wait=false
oc delete configmap chaos-config -n comm-platform --ignore-not-found
oc delete namespace comm-platform --ignore-not-found

echo "Cleanup complete: removed comm-platform namespace and resources"
