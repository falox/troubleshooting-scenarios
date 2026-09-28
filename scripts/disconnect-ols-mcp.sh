#!/usr/bin/env bash
set -euo pipefail

echo "==> Removing MCP servers from OLSConfig..."
oc patch olsconfig cluster --type=json \
  -p='[{"op":"remove","path":"/spec/mcpServers"}]' 2>/dev/null || true

echo "==> Restarting lightspeed-app-server..."
oc rollout restart deployment/lightspeed-app-server -n openshift-lightspeed 2>/dev/null || true
oc rollout status deployment/lightspeed-app-server -n openshift-lightspeed --timeout=300s 2>/dev/null || true

echo "==> OLS disconnected from MCP."
