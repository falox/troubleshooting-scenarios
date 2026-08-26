#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"

"$SCRIPT_DIR/enable-uwm.sh"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

echo "Setup complete: email-dispatcher-rules PrometheusRule deployed"
