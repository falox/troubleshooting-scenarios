#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc apply -f "$FIXTURE_DIR/namespace.yaml"

echo "Setup complete: namespace out-of-scope created (no fixtures needed)"
