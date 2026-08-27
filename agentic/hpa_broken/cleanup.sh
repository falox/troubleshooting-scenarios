#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="product-catalog"

oc delete hpa catalog-api -n "$NS" --ignore-not-found
oc delete deployment catalog-api -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed product-catalog namespace and resources"
