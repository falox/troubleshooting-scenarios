#!/usr/bin/env bash
set -euo pipefail

MCP_NS="${MCP_NS:-openshift-mcp}"
MCP_DEPLOYMENT="${MCP_DEPLOYMENT:-openshift-mcp-server}"
MCP_IMAGE="${MCP_IMAGE:-registry.redhat.io/openshift-mcp/openshift-mcp-server-rhel9@sha256:a551fd58f7b2a7505a76ba2109ae5a8f031606605490c9c68d60f91f502f6fe5}"
MCP_COMMAND="${MCP_COMMAND:-/openshift-mcp-server}"
MCP_CONFIG_MOUNT="${MCP_CONFIG_MOUNT:-/etc/mcp}"
MCP_TOOLSETS="${MCP_TOOLSETS:-core,config}"
MCP_KIALI_URL="${MCP_KIALI_URL:-}"
MCP_ROLLOUT_TIMEOUT="${MCP_ROLLOUT_TIMEOUT:-120s}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Creating namespace ${MCP_NS}..."
oc create namespace "$MCP_NS" --dry-run=client -o yaml | oc apply -f -

echo "==> Creating ServiceAccount ${MCP_DEPLOYMENT}..."
oc apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${MCP_DEPLOYMENT}
  namespace: ${MCP_NS}
EOF

echo "==> Granting cluster-admin to ServiceAccount..."
oc create clusterrolebinding "${MCP_DEPLOYMENT}-admin" \
  --clusterrole=cluster-admin \
  "--serviceaccount=${MCP_NS}:${MCP_DEPLOYMENT}" \
  --dry-run=client -o yaml | oc apply -f -

# Build config.toml
bash "${SCRIPT_DIR}/mcp-config.sh" --no-restart
config_checksum="$(oc get configmap mcp-config -n "$MCP_NS" -o 'jsonpath={.data.config\.toml}' | sha256sum)"
config_checksum="${config_checksum%% *}"

config_file="${MCP_CONFIG_MOUNT}/config.toml"

echo "==> Creating Deployment ${MCP_DEPLOYMENT}..."
oc apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${MCP_DEPLOYMENT}
  namespace: ${MCP_NS}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${MCP_DEPLOYMENT}
  template:
    metadata:
      annotations:
        mcp-config-hash: "${config_checksum}"
      labels:
        app: ${MCP_DEPLOYMENT}
    spec:
      serviceAccountName: ${MCP_DEPLOYMENT}
      containers:
      - name: ${MCP_DEPLOYMENT}
        image: ${MCP_IMAGE}
        command: ["${MCP_COMMAND}"]
        args: ["--config", "${config_file}"]
        ports:
        - containerPort: 8080
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          seccompProfile:
            type: RuntimeDefault
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: mcp-config
          mountPath: ${MCP_CONFIG_MOUNT}
      volumes:
      - name: mcp-config
        configMap:
          name: mcp-config
EOF

echo "==> Creating Service ${MCP_DEPLOYMENT}..."
oc apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${MCP_DEPLOYMENT}
  namespace: ${MCP_NS}
spec:
  selector:
    app: ${MCP_DEPLOYMENT}
  ports:
  - port: 8080
    targetPort: 8080
EOF

if ! oc rollout status "deployment/${MCP_DEPLOYMENT}" -n "$MCP_NS" --timeout="$MCP_ROLLOUT_TIMEOUT"; then
  oc get pods -n "$MCP_NS" -l "app=${MCP_DEPLOYMENT}" >&2 || true
  oc logs -n "$MCP_NS" -l "app=${MCP_DEPLOYMENT}" --all-containers=true --prefix=true --tail=40 >&2 || true
  exit 1
fi

echo ""
echo "==> MCP server ready in ${MCP_NS}"
echo "==> In-cluster: http://${MCP_DEPLOYMENT}.${MCP_NS}.svc.cluster.local:8080/mcp"
