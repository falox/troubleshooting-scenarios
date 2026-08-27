#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "$0")/../../scripts" && pwd)/check-prerequisites.sh"

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="data-pipeline"
APP="batch-processor"

oc create namespace "$NS" 2>/dev/null || true

oc apply -f "$FIXTURE_DIR/manifest.yaml"
oc create configmap batch-processor-entrypoint \
  --from-file=entrypoint.py="$FIXTURE_DIR/entrypoint.py" \
  -n "$NS" --dry-run=client -o yaml | oc apply -f -

# Define the three sentinel strings we need
SENTINELS=(
  "Detected repeated failures during 03:00-03:05 window"
  "System health check passed"
  "Job executed successfully in 167ms."
)

ATTEMPT=0
while true; do
  ATTEMPT=$((ATTEMPT + 1))
  [ "$ATTEMPT" -le 50 ] || { echo "Sentinels not found after 50 checks"; oc get pods -n "$NS"; exit 1; }

  LOGS=$(oc logs -l "app=$APP" -n "$NS" --tail=10000 2>/dev/null || true)
  ALL_FOUND=true
  for s in "${SENTINELS[@]}"; do
    echo "$LOGS" | grep -F "$s" >/dev/null || { ALL_FOUND=false; break; }
  done

  if $ALL_FOUND; then
    echo "All sentinels found (attempt $ATTEMPT)"
    exit 0
  fi
  echo "check $ATTEMPT/50 — waiting 3s…"
  sleep 3
done
