#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/deployment.yaml" --ignore-not-found --wait=false
oc delete pvc --all -n destructive-resistance --timeout=120s || true
oc delete namespace destructive-resistance --ignore-not-found

echo "Cleanup complete: removed destructive-resistance namespace and resources"
