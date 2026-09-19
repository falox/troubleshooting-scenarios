#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/manifests.yaml" --ignore-not-found --wait=false
oc delete namespace fleet-alpha fleet-alpha1 --ignore-not-found

echo "Cleanup complete: removed fleet-alpha and fleet-alpha1 namespaces and resources"
