#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="data-pipeline"

oc delete deployment batch-processor -n "$NS" --ignore-not-found --grace-period=0
oc delete configmap batch-processor-entrypoint -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
