#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="booking-service"

oc delete deployment booking-app -n "$NS" --ignore-not-found
oc delete configmap app-settings -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
