#!/usr/bin/env bash
set -euo pipefail

oc delete namespace out-of-scope --ignore-not-found

echo "Cleanup complete: removed out-of-scope namespace"
