#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

NS="notification-hub"

echo "Removing svc_port_mismatch scenario resources from namespace ${NS}…"
oc delete deployment notifier-app -n "$NS" --ignore-not-found
oc delete svc notifier-svc -n "$NS" --ignore-not-found

oc delete namespace "$NS" --ignore-not-found
echo "Cleanup complete — all svc_port_mismatch scenario resources removed."
