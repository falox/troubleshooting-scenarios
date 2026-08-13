#!/usr/bin/env bash
set -euo pipefail

NS="missing-pvc-test"

echo "Removing missing_pvc scenario resources from namespace ${NS}…"
oc delete -f "$(cd "$(dirname "$0")/fixtures" && pwd)/manifest.yaml" --ignore-not-found
# Remove any PVCs the agent may have created during remediation.
oc delete pvc --all -n "$NS" --timeout=120s || true

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all missing_pvc scenario resources removed."
