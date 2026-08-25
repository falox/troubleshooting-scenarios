#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/deployment.yaml" --ignore-not-found --wait=false
oc delete namespace config-drift --ignore-not-found

echo "Cleanup complete: removed config-drift namespace and resources"
