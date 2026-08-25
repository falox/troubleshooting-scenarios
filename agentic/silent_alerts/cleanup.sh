#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc delete -f "$FIXTURE_DIR/prometheusrule.yaml" --ignore-not-found
oc delete namespace silent-alerts --ignore-not-found

echo "Cleanup complete: removed silent-alerts namespace and resources"
