#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../../scripts" && pwd)"

OLS_NS="${OLS_NS:-openshift-lightspeed}"
MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"
CNV_NS="${CNV_NS:-openshift-cnv}"
KUBECTL="${KUBECTL:-oc}"
CNV_STATE_FILE="${CNV_STATE_FILE:-${TMPDIR:-/tmp}/troubleshooting-scenarios-kubevirt-cnv-created}"

echo "==> Disconnecting OLS from MCP server..."
OLS_NS="$OLS_NS" bash "$SCRIPTS_DIR/disconnect-ols-mcp.sh" || true

echo "==> Removing MCP server..."
MCP_NS="$MCP_NS" MCP_DEPLOYMENT="$MCP_DEPLOYMENT" \
  bash "$SCRIPTS_DIR/cleanup-mcp.sh" || true

if [[ -f "${CNV_STATE_FILE}" ]]; then
  echo "==> Removing OpenShift Virtualization installed by this run..."
  if CNV_NS="$CNV_NS" KUBECTL="$KUBECTL" bash "$SCRIPT_DIR/scripts/uninstall-cnv.sh"; then
    rm -f "${CNV_STATE_FILE}"
  else
    echo "WARNING: CNV cleanup failed; retaining ownership marker for a retry."
  fi
else
  echo "==> Preserving pre-existing OpenShift Virtualization."
fi
