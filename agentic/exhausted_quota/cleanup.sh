#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="team-onboarding"

oc delete -f "$FIXTURE_DIR/prometheusrule.yaml" --ignore-not-found
oc delete deployment onboarding-app -n "$NS" --ignore-not-found
oc delete deployment setup-worker -n "$NS" --ignore-not-found
oc delete resourcequota team-pod-quota -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
