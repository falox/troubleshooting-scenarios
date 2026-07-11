#!/usr/bin/env bash
# Check that OpenShift Virtualization is installed and healthy.
# Exits 0 if ready, 1 if not installed or not healthy.
set -euo pipefail

CNV_NS="${CNV_NS:-openshift-cnv}"
KUBECTL="${KUBECTL:-oc}"

echo "==> Checking OpenShift Virtualization..."

csv=$($KUBECTL get csv -n "${CNV_NS}" --no-headers 2>/dev/null \
  | awk '/kubevirt-hyperconverged/ {print $1; exit}')
if [[ -z "${csv}" ]]; then
  echo "ERROR: OpenShift Virtualization is NOT installed in namespace ${CNV_NS}."
  echo "  Install it from OperatorHub before running these scenarios."
  exit 1
fi

phase=$($KUBECTL get csv "${csv}" -n "${CNV_NS}" -o jsonpath='{.status.phase}' 2>/dev/null || true)
if [[ "${phase}" != "Succeeded" ]]; then
  echo "ERROR: CNV operator CSV is in phase '${phase}' (expected Succeeded)"
  exit 1
fi

hco=$($KUBECTL get hyperconverged kubevirt-hyperconverged -n "${CNV_NS}" \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
if [[ -z "${hco}" ]]; then
  echo "ERROR: HyperConverged CR kubevirt-hyperconverged not found in ${CNV_NS}"
  exit 1
fi
if [[ "${hco}" != "True" ]]; then
  echo "ERROR: HyperConverged CR is not Available (status=${hco})"
  exit 1
fi

echo "==> OpenShift Virtualization is healthy (${csv}, phase=${phase})"

kvm_total=$($KUBECTL get nodes -l node-role.kubernetes.io/worker \
  -o jsonpath='{range .items[*]}{.status.allocatable.devices\.kubevirt\.io/kvm}{"\n"}{end}' 2>/dev/null \
  | awk '{s+=$1} END{print s+0}')
if [[ "${kvm_total}" -eq 0 ]]; then
  echo "WARNING: No KVM devices on worker nodes. Scenarios that require a running VM will be skipped."
fi
