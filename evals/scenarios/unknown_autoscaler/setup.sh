#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"
NS="product-catalog"
DEPLOY="catalog-api"

"$SCRIPT_DIR/enable-uwm.sh"
oc apply -f "$FIXTURE_DIR/manifest.yaml"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

echo "Waiting for deployment $DEPLOY to become available..."
oc wait --for=condition=Available deployment/"$DEPLOY" \
  -n "$NS" --timeout=120s

echo "Waiting for the HPA to report failed metrics (ScalingActive=False)..."
oc wait --for=condition=ScalingActive=false hpa/"$DEPLOY" \
  -n "$NS" --timeout=120s

echo "Setup complete: HPA reports ScalingActive=False"

"$SCRIPT_DIR/wait-for-alert.sh" "ProductCatalogHpaInactive" "" 600
