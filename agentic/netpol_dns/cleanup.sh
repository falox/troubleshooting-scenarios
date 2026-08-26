#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="netpol-dns-test"

echo "Removing netpol_dns scenario resources from namespace ${NS}…"
oc delete -f "$(cd "$(dirname "$0")/fixtures" && pwd)/manifest.yaml" --ignore-not-found
# Remove any NetworkPolicies the agent may have created during remediation.
oc delete networkpolicy --all -n "$NS" --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all netpol_dns scenario resources removed."
