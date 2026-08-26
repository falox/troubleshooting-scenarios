#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="overprivileged-demo"

oc delete deployment overprivileged-webapp -n "$NS" --ignore-not-found
oc delete rolebinding webapp-admin-binding -n "$NS" --ignore-not-found
oc delete serviceaccount webapp-sa -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed overprivileged-demo namespace and resources"
