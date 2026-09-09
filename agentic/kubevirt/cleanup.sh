#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../scripts" && pwd)"

OLS_NS="${OLS_NS:-openshift-lightspeed}"
MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"

echo "==> Disconnecting OLS from MCP server..."
OLS_NS="$OLS_NS" bash "$SCRIPTS_DIR/disconnect-ols-mcp.sh" || true

echo "==> Removing MCP server..."
MCP_NS="$MCP_NS" MCP_DEPLOYMENT="$MCP_DEPLOYMENT" \
  bash "$SCRIPTS_DIR/cleanup-mcp.sh" || true

if [ -f "$SCRIPT_DIR/.cnv-installed-by-scenario" ] || [ "${FORCE_CNV_CLEANUP:-false}" == "true" ]; then
  echo "==> Removing OpenShift Virtualization..."
  bash "$SCRIPT_DIR/scripts/uninstall-cnv.sh" || true
  rm -f "$SCRIPT_DIR/.cnv-installed-by-scenario"
else
  echo "==> Skipping OpenShift Virtualization removal (was pre-existing)."
fi
