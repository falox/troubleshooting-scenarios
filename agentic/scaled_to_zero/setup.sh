#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Setup complete: scaled-to-zero-demo deployed with 0 replicas"
