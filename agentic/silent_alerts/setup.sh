#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"

"$SCRIPT_DIR/enable-uwm.sh"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

echo "Setup complete: silent-alert-rules PrometheusRule deployed"
