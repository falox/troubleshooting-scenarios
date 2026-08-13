#!/usr/bin/env bash
set -euo pipefail

NS="priorityclass-test"

echo "Removing priorityclass scenario resources from namespace ${NS}…"
oc delete -f "$(cd "$(dirname "$0")/fixtures" && pwd)/manifest.yaml" --ignore-not-found
# Remove PriorityClass if the agent created it during remediation.
oc delete priorityclass eval-critical-priority --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all priorityclass scenario resources removed."
