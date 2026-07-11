#!/usr/bin/env bash
# KVM availability check for kubevirt scenarios.
#
# Sourced by setup.sh:  source require-kvm.sh; require_kvm
#   Exits the caller with 0 (skip) if no KVM devices are available.
#
# Standalone:  bash require-kvm.sh --check
#   Exits 0 if KVM available, 1 if not. No output.

KUBECTL="${KUBECTL:-oc}"

_kvm_available() {
  local total
  total=$(${KUBECTL} get nodes -l node-role.kubernetes.io/worker \
    -o jsonpath='{range .items[*]}{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}{end}' 2>/dev/null \
    | awk '{s+=$1} END{print s+0}')
  [[ "${total}" -gt 0 ]]
}

require_kvm() {
  if ! _kvm_available; then
    echo "SKIP: No KVM devices on worker nodes. This scenario requires KVM-capable nodes."
    echo "      Use bare-metal instances or set useEmulation: true on the KubeVirt CR."
    exit 0
  fi
}

if [[ "${1:-}" == "--check" ]]; then
  _kvm_available
fi
