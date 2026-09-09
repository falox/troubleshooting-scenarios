#!/usr/bin/env bash
KUBECTL=${KUBECTL:-oc} # kubectl for kind, oc for OpenShift (set via CLUSTER env)
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
WAIT_SECONDS=${WAIT_SECONDS:-180} # override with: make all WAIT_SECONDS=60

echo "Removing routing manifests…"
${KUBECTL} delete -f "$FIXTURE_DIR/manifests.yaml" --ignore-not-found

echo "Waiting ${WAIT_SECONDS}s for Istio metrics to stabilise after routing manifests removal…"
sleep "$WAIT_SECONDS"
echo "Cleanup complete — routing to 50/50 in v1/v2 removed."
