#!/usr/bin/env bash
set -euo pipefail

oc delete namespace imagepull-auth --ignore-not-found

echo "Cleanup complete: removed imagepull-auth namespace"
