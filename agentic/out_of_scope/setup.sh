#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc apply -f "$FIXTURE_DIR/namespace.yaml"

echo "Setup complete: namespace out-of-scope created (no fixtures needed)"
