#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="product-catalog"
DEPLOY="catalog-api"

oc apply -f "$FIXTURE_DIR/manifest.yaml"

# Wait for the deployment to become available
echo "Waiting for deployment $DEPLOY to become available…"
oc wait --for=condition=Available deployment/"$DEPLOY" \
  -n "$NS" --timeout=120s

# Wait for the HPA to report failed metrics (ScalingActive=False)
echo "Waiting for the HPA to report failed metrics (ScalingActive=False)…"
oc wait --for=condition=ScalingActive=false hpa/"$DEPLOY" \
  -n "$NS" --timeout=120s

echo "Setup complete: HPA reports ScalingActive=False"
