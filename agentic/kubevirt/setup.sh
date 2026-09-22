#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../scripts" && pwd)"

MCP_TOOLSETS="${MCP_TOOLSETS:-core,config,kubevirt}"
MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"
MCP_OLS_NAME="${MCP_OLS_NAME:-openshift-mcp}"
OLS_NS="${OLS_NS:-openshift-lightspeed}"
CNV_NS="${CNV_NS:-openshift-cnv}"
KUBECTL="${KUBECTL:-oc}"
CNV_STATE_FILE="${CNV_STATE_FILE:-${TMPDIR:-/tmp}/troubleshooting-scenarios-kubevirt-cnv-created}"

# A stale marker must never grant ownership of an existing installation.
rm -f "${CNV_STATE_FILE}"

cnv_namespace_exists() {
  "${KUBECTL}" get namespace "${CNV_NS}" >/dev/null 2>&1
}

if cnv_namespace_exists; then
  echo "==> CNV namespace already exists. Preserving its resources."
  CNV_NS="$CNV_NS" KUBECTL="$KUBECTL" bash "$SCRIPT_DIR/scripts/check-cnv.sh"
else
  echo "==> Installing OpenShift Virtualization..."
  : > "${CNV_STATE_FILE}"
  CNV_NS="$CNV_NS" KUBECTL="$KUBECTL" bash "$SCRIPT_DIR/scripts/install-cnv.sh"
  CNV_NS="$CNV_NS" KUBECTL="$KUBECTL" CNV_MANAGED_BY_SCENARIO=1 \
    bash "$SCRIPT_DIR/scripts/check-cnv.sh"
fi

echo "==> Deploying MCP server (toolsets: ${MCP_TOOLSETS})..."
MCP_NS="$MCP_NS" MCP_DEPLOYMENT="$MCP_DEPLOYMENT" MCP_TOOLSETS="$MCP_TOOLSETS" \
  bash "$SCRIPTS_DIR/setup-mcp.sh"

echo "==> Connecting OLS to MCP server..."
MCP_NS="$MCP_NS" MCP_DEPLOYMENT="$MCP_DEPLOYMENT" MCP_OLS_NAME="$MCP_OLS_NAME" \
  OLS_NS="$OLS_NS" \
  bash "$SCRIPTS_DIR/connect-ols-mcp.sh"
