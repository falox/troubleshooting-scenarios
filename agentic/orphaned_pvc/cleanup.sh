#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/manifest.yaml" --ignore-not-found --wait=false
oc delete namespace pvc-orphans --ignore-not-found

echo "Cleanup complete: removed pvc-orphans namespace and resources"
