#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="analytics-dashboard"

oc delete deployment dashboard-app -n "$NS" --ignore-not-found
oc delete limitrange eval-container-limits -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed analytics-dashboard namespace and resources"
