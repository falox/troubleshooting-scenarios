#!/usr/bin/env bash
set -euo pipefail

# Build and apply the MCP server config.toml ConfigMap.
# Called by setup-mcp.sh and can be called standalone to reconfigure.

MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"
MCP_TOOLSETS="${MCP_TOOLSETS:-core,config}"
MCP_KIALI_URL="${MCP_KIALI_URL:-}"
MCP_ROLLOUT_TIMEOUT="${MCP_ROLLOUT_TIMEOUT:-120s}"

restart=true
case "${1:-}" in
  "") ;;
  --no-restart) restart=false ;;
  *) echo "Usage: $0 [--no-restart]" >&2; exit 2 ;;
esac

# Build toolsets array: ["core","config","ossm",...]
ts='["core","config"'
IFS=,
for t in $MCP_TOOLSETS; do
  t="$(echo "$t" | tr -d ' ')"
  [ "$t" = "core" ] || [ "$t" = "config" ] || ts="${ts},\"${t}\""
done
unset IFS
ts="${ts}]"

echo "==> Building mcp-config in ${MCP_NS} (toolsets: ${ts})..."

config="$(printf 'toolsets = %s\nlog_level = 0\nport = "8080"\nread_only = true\n' "$ts")"

if [ -n "$MCP_KIALI_URL" ]; then
  config="${config}
[toolset_configs.kiali]
url = \"${MCP_KIALI_URL}\"
insecure = true"
fi

echo "$config"

echo "$config" | oc create configmap mcp-config \
  --from-file=config.toml=/dev/stdin \
  -n "$MCP_NS" --dry-run=client -o yaml | oc apply -f -

# Restart if deployment exists
if [ "$restart" = true ] && oc get deployment "$MCP_DEPLOYMENT" -n "$MCP_NS" &>/dev/null; then
  echo "==> Restarting ${MCP_DEPLOYMENT}..."
  oc rollout restart "deployment/${MCP_DEPLOYMENT}" -n "$MCP_NS"
  if ! oc rollout status "deployment/${MCP_DEPLOYMENT}" -n "$MCP_NS" --timeout="$MCP_ROLLOUT_TIMEOUT"; then
    oc get pods -n "$MCP_NS" -l "app=${MCP_DEPLOYMENT}" >&2 || true
    oc logs -n "$MCP_NS" -l "app=${MCP_DEPLOYMENT}" --all-containers=true --prefix=true --tail=40 >&2 || true
    exit 1
  fi
fi
