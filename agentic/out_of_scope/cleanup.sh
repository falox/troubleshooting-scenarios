#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

oc delete namespace out-of-scope --ignore-not-found

echo "Cleanup complete: removed out-of-scope namespace"
