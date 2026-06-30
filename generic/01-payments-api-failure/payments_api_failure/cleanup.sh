#!/usr/bin/env bash
set -euo pipefail

KUBECTL=${KUBECTL:-oc}

echo "=== Deleting namespaces ==="
${KUBECTL} delete namespace shared-services payments --ignore-not-found --wait

echo "Cleanup complete."
