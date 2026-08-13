#!/usr/bin/env bash
set -euo pipefail

NS="ha-services"

oc delete deployment antiaffinity-demo -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
