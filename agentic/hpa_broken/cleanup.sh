#!/usr/bin/env bash
set -euo pipefail

NS="hpa-scaling"

oc delete hpa hpa-underspecified-demo -n "$NS" --ignore-not-found
oc delete deployment hpa-underspecified-demo -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed hpa-scaling namespace and resources"
