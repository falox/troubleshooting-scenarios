#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="team-onboarding"

oc delete deployment quota-victim-app -n "$NS" --ignore-not-found
oc delete deployment quota-blocker -n "$NS" --ignore-not-found
oc delete resourcequota team-pod-quota -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
