#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(cd "$SCRIPT_DIR/../../scripts" && pwd)"

NETOBSERV_INSTALL_SCRIPT="$SCRIPT_DIR/scripts/install-netobserv-release.sh"
NETOBSERV_FLOWCOLLECTOR_FILE="${NETOBSERV_FLOWCOLLECTOR_FILE:-$SCRIPT_DIR/scripts/flowcollector.yaml}"
NETOBSERV_NS="${NETOBSERV_NS:-netobserv}"
NETOBSERV_OPERATOR_NS="${NETOBSERV_OPERATOR_NS:-openshift-netobserv-operator}"
KUBERNETES_CLI="${KUBERNETES_CLI:-oc}"
NETOBSERV_CATALOG_SOURCE="${NETOBSERV_CATALOG_SOURCE:-redhat}"
NETOBSERV_CHANNEL="${NETOBSERV_CHANNEL:-}"
NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT="${NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT:-10m}"

MCP_TOOLSETS="${MCP_TOOLSETS:-core,config,netobserv}"
MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"
MCP_OLS_NAME="${MCP_OLS_NAME:-openshift-mcp}"
OLS_NS="${OLS_NS:-openshift-lightspeed}"

NETOBSERV_INSTALL_FLAGS=(
  -c "$KUBERNETES_CLI"
  -ns "$NETOBSERV_NS"
  -ons "$NETOBSERV_OPERATOR_NS"
  -cs "$NETOBSERV_CATALOG_SOURCE"
  -fc "$NETOBSERV_FLOWCOLLECTOR_FILE"
)
if [[ -n "$NETOBSERV_CHANNEL" ]]; then
  NETOBSERV_INSTALL_FLAGS+=( -ch "$NETOBSERV_CHANNEL" )
fi

echo "==> Installing NetObserv operator..."
bash "$NETOBSERV_INSTALL_SCRIPT" "${NETOBSERV_INSTALL_FLAGS[@]}" install-operator

echo "==> Deploying MCP server (toolsets: ${MCP_TOOLSETS})..."
MCP_NS="$MCP_NS" MCP_DEPLOYMENT="$MCP_DEPLOYMENT" MCP_TOOLSETS="$MCP_TOOLSETS" \
  bash "$SCRIPTS_DIR/setup-mcp.sh"

echo "==> Connecting OLS to MCP server..."
MCP_NS="$MCP_NS" MCP_DEPLOYMENT="$MCP_DEPLOYMENT" MCP_OLS_NAME="$MCP_OLS_NAME" \
  OLS_NS="$OLS_NS" \
  bash "$SCRIPTS_DIR/connect-ols-mcp.sh"

echo "==> Installing NetObserv FlowCollector..."
NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT="$NETOBSERV_FLOWCOLLECTOR_WAIT_TIMEOUT" \
  bash "$NETOBSERV_INSTALL_SCRIPT" "${NETOBSERV_INSTALL_FLAGS[@]}" install-flowcollector
