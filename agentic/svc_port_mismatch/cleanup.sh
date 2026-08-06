#!/usr/bin/env bash
set -euo pipefail

NS="svc-port-demo"

echo "Removing svc_port_mismatch scenario resources from namespace ${NS}…"
oc delete deployment svc-port-demo -n "$NS" --ignore-not-found
oc delete svc svc-port-svc -n "$NS" --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all svc_port_mismatch scenario resources removed."
