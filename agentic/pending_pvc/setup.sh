#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")/../../scripts" && pwd)"
NS="cache-tier"
PVC="memcached-data-pvc"

"$SCRIPT_DIR/enable-uwm.sh"
oc apply -f "$FIXTURE_DIR/manifest.yaml"
oc apply -f "$FIXTURE_DIR/prometheusrule.yaml"

# Wait for ProvisioningFailed event on the PVC
echo "Waiting for ProvisioningFailed event on $PVC…"
FOUND=false
ATTEMPT=0
until [ "$ATTEMPT" -ge 60 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATUS=$(oc get events -n "$NS" \
    --field-selector "involvedObject.name=$PVC,involvedObject.kind=PersistentVolumeClaim" \
    -o jsonpath='{.items[*].reason}' 2>/dev/null || true)
  if echo "$STATUS" | grep -q "ProvisioningFailed"; then
    echo "Setup complete: ProvisioningFailed event detected (attempt $ATTEMPT)"
    FOUND=true
    break
  fi
  sleep 1
done

if [ "$FOUND" != "true" ]; then
  echo "ProvisioningFailed event not detected within 60s"
  oc describe pvc "$PVC" -n "$NS"
  exit 1
fi

"$SCRIPT_DIR/wait-for-alert.sh" "CacheTierPersistentVolumeClaimPending"
