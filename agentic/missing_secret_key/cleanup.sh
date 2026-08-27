#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="credential-store"

oc delete deployment credential-app -n "$NS" --ignore-not-found
oc delete secret db-creds -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
