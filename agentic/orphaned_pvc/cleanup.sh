#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/manifest.yaml" --ignore-not-found --wait=false
oc delete namespace artifact-storage --ignore-not-found

echo "Cleanup complete: removed artifact-storage namespace and resources"
