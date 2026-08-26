#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

oc delete namespace imagepull-auth --ignore-not-found

echo "Cleanup complete: removed imagepull-auth namespace"
