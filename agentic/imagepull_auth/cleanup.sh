#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

oc delete namespace media-processing --ignore-not-found

echo "Cleanup complete: removed media-processing namespace"
