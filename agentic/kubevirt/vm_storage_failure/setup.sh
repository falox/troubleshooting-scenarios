#!/usr/bin/env bash
set -euo pipefail

KUBECTL=${KUBECTL:-oc}
NAMESPACE=${NAMESPACE:-kubevirt-scenarios}
FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"

echo "==> Deploying VM storage failure scenario in namespace ${NAMESPACE}..."
echo "    VM uses non-existent StorageClass 'premium-nvme-storage' and will be stuck in Provisioning."

${KUBECTL} create namespace "${NAMESPACE}" --dry-run=client -o yaml | ${KUBECTL} apply -f -
${KUBECTL} apply -f "${FIXTURE_DIR}/vm.yaml" -n "${NAMESPACE}"

echo "==> Waiting for DataVolume to report missing StorageClass..."
detected=false
for _ in $(seq 1 30); do
  dv_events=$(${KUBECTL} get events -n "${NAMESPACE}" 2>/dev/null || true)
  if echo "$dv_events" | grep -qi "premium-nvme-storage.*not found"; then
    detected=true
    break
  fi
  sleep 5
done

if [[ "${detected}" == "false" ]]; then
  echo "ERROR: Timed out waiting for missing-StorageClass provisioning failure."
  exit 1
fi

echo "==> VM status:"
${KUBECTL} get vm production-db-vm -n "${NAMESPACE}" -o wide 2>/dev/null || echo "    VM not found"
echo ""
echo "==> DataVolume status:"
${KUBECTL} get dv production-db-vm-volume -n "${NAMESPACE}" 2>/dev/null || echo "    No DataVolume"
echo ""
echo "==> Setup complete. Ask the AI:"
echo '    "Why is VM production-db-vm not starting in namespace '"${NAMESPACE}"'?"'
