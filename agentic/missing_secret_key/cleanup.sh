#!/usr/bin/env bash
set -euo pipefail

NS="credential-store"

oc delete deployment missing-secret-key-demo -n "$NS" --ignore-not-found
oc delete secret db-creds -n "$NS" --ignore-not-found
oc delete namespace "$NS" --ignore-not-found

echo "Cleanup complete: removed $NS namespace and resources"
