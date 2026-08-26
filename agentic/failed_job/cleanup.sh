#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/job.yaml" --ignore-not-found --wait=false
oc delete secret inventory-sync-logs-script -n catalog-mgmt --ignore-not-found
oc delete namespace catalog-mgmt --ignore-not-found

echo "Cleanup complete: removed catalog-mgmt namespace and resources"
