#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="limitrange-demo"

oc delete deployment limitrange-demo -n "$NS" --ignore-not-found
oc delete limitrange eval-container-limits -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed limitrange-demo namespace and resources"
