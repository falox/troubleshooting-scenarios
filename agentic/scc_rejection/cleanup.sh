#!/usr/bin/env bash
set -euo pipefail

NS="legacy-migration"

oc delete deployment scc-demo -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
