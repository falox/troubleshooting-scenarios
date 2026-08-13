#!/usr/bin/env bash
set -euo pipefail

NS="multi-issue-app"

oc delete deployment double-fault-demo -n "$NS" --ignore-not-found
oc delete configmap df-settings -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
