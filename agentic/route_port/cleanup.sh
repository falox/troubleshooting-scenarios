#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="customer-portal"

echo "Removing route_port scenario resources from namespace ${NS}…"
oc delete -f "$(cd "$(dirname "$0")/fixtures" && pwd)/manifest.yaml" --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete: removed customer-portal namespace and resources"
