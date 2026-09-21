#!/usr/bin/env bash
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCENARIO_DIR/../../../scripts" && pwd)"
FIXTURE_DIR="$SCENARIO_DIR/fixtures"
IMAGE_DIR="$SCENARIO_DIR/image"
NS="data-pipeline"
APP="batch-processor"
REGISTRY_NAMESPACE="openshift-image-registry"
REGISTRY_SERVICE="image-registry"
REGISTRY_LOCAL_PORT="${REGISTRY_LOCAL_PORT:-5000}"
IMAGE_TAG="${BATCH_PROCESSOR_IMAGE_TAG:-1.0.0}"
PUSH_REGISTRY="localhost:${REGISTRY_LOCAL_PORT}"
REGISTRY_REPOSITORY="${NS}/${APP}"
CLUSTER_REGISTRY="image-registry.openshift-image-registry.svc:5000"
LOCAL_IMAGE="${APP}:${IMAGE_TAG}"
PUSH_IMAGE="${PUSH_REGISTRY}/${REGISTRY_REPOSITORY}:${IMAGE_TAG}"
RENDERED_MANIFEST=""
TMP_DIR=""
REGISTRY_PORT_FORWARD_PID=""

"$SCRIPTS_DIR/check-prerequisites.sh"

for command_name in podman curl timeout python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "ERROR: '$command_name' is required by the batch processor fixture" >&2
    exit 1
  fi
done

if ! [[ "$REGISTRY_LOCAL_PORT" =~ ^[1-9][0-9]*$ ]] || [ "$REGISTRY_LOCAL_PORT" -gt 65535 ]; then
  echo "ERROR: REGISTRY_LOCAL_PORT must be between 1 and 65535" >&2
  exit 1
fi

normalize_arch() {
  case "$1" in
    amd64|x86_64) printf 'amd64\n' ;;
    arm64|aarch64) printf 'arm64\n' ;;
    ppc64le) printf 'ppc64le\n' ;;
    s390x) printf 's390x\n' ;;
    *) return 1 ;;
  esac
}

LOCAL_ARCH_RAW="$(podman info --format '{{.Host.Arch}}')"
LOCAL_ARCH="$(normalize_arch "$LOCAL_ARCH_RAW")" || {
  echo "ERROR: unsupported local Podman architecture: $LOCAL_ARCH_RAW" >&2
  exit 1
}

NODE_ARCHES="$(oc get nodes -o jsonpath='{range .items[*]}{.metadata.labels.kubernetes\.io/arch}{"\n"}{end}')"
if [ -z "$NODE_ARCHES" ]; then
  echo "ERROR: no OpenShift node architectures were returned" >&2
  exit 1
fi

ARCH_MATCH=false
while IFS= read -r node_arch; do
  [ -n "$node_arch" ] || continue
  normalized_node_arch="$(normalize_arch "$node_arch")" || continue
  if [ "$normalized_node_arch" = "$LOCAL_ARCH" ]; then
    ARCH_MATCH=true
    break
  fi
done <<< "$NODE_ARCHES"
if [ "$ARCH_MATCH" != true ]; then
  echo "ERROR: local architecture $LOCAL_ARCH does not match any cluster node" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
AUTHFILE="$TMP_DIR/auth.json"
REGISTRY_LOG="$TMP_DIR/registry-port-forward.log"
RENDERED_MANIFEST="$TMP_DIR/manifest.yaml"

cleanup_runtime() {
  if [ -n "$REGISTRY_PORT_FORWARD_PID" ]; then
    kill "$REGISTRY_PORT_FORWARD_PID" 2>/dev/null || true
    wait "$REGISTRY_PORT_FORWARD_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup_runtime EXIT

if oc get namespace "$NS" >/dev/null 2>&1; then
  namespace_phase="$(oc get namespace "$NS" -o jsonpath='{.status.phase}')"
  namespace_deleting="$(oc get namespace "$NS" -o jsonpath='{.metadata.deletionTimestamp}')"
  if [ "$namespace_phase" = "Terminating" ] || [ -n "$namespace_deleting" ]; then
    echo "Waiting for namespace/$NS deletion to complete..."
    for _ in $(seq 1 90); do
      if ! oc get namespace "$NS" >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
  fi
fi

if oc get namespace "$NS" >/dev/null 2>&1; then
  echo "ERROR: namespace/$NS already exists; run cleanup before setup" >&2
  exit 1
fi

oc create -f "$FIXTURE_DIR/namespace.yaml"

echo "Building $LOCAL_IMAGE..."
podman build --tag "$LOCAL_IMAGE" "$IMAGE_DIR"

echo "Starting internal registry port-forward..."
oc port-forward \
  -n "$REGISTRY_NAMESPACE" \
  "service/$REGISTRY_SERVICE" \
  "${REGISTRY_LOCAL_PORT}:5000" >"$REGISTRY_LOG" 2>&1 &
REGISTRY_PORT_FORWARD_PID=$!

registry_ready=false
for _ in $(seq 1 30); do
  status_code="$(curl -k -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 2 --max-time 5 "https://${PUSH_REGISTRY}/v2/" 2>/dev/null || true)"
  case "$status_code" in
    200|401|403)
      registry_ready=true
      break
      ;;
  esac
  sleep 1
done

if [ "$registry_ready" != true ]; then
  echo "ERROR: internal registry port-forward did not become ready" >&2
  cat "$REGISTRY_LOG" >&2 || true
  exit 1
fi

echo "Authenticating to the internal registry..."
oc registry login \
  --registry="$PUSH_REGISTRY" \
  --insecure \
  --to="$AUTHFILE"

podman tag "$LOCAL_IMAGE" "$PUSH_IMAGE"
echo "Pushing $PUSH_IMAGE..."
podman push \
  --authfile "$AUTHFILE" \
  --tls-verify=false \
  --digestfile "$TMP_DIR/image.digest" \
  "$PUSH_IMAGE"

IMAGE_DIGEST="$(cat "$TMP_DIR/image.digest")"
if ! [[ "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "ERROR: image push did not return a valid digest" >&2
  exit 1
fi

sed "s|IMAGE_PLACEHOLDER|${CLUSTER_REGISTRY}/${REGISTRY_REPOSITORY}@${IMAGE_DIGEST}|g" \
  "$FIXTURE_DIR/manifest.yaml" >"$RENDERED_MANIFEST"
oc apply -f "$RENDERED_MANIFEST"

echo "Waiting for deployment/$APP..."
oc wait --for=condition=Available "deployment/$APP" \
  -n "$NS" --timeout=180s

LOGS="$(oc logs "deployment/$APP" -n "$NS" --tail=10000)"
printf '%s\n' "$LOGS" >"$TMP_DIR/application.log"
python3 - "$TMP_DIR/application.log" <<'PY'
import json
import sys

entries = []
with open(sys.argv[1], encoding="utf-8") as log_file:
    for line in log_file:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("event") == "batch_submission":
            entries.append(entry)

timeout_dates = {
    entry["event_time"][:10]
    for entry in entries
    if entry.get("result") == "timeout"
}
has_success = any(entry.get("result") == "success" for entry in entries)

if len(timeout_dates) < 3:
    raise SystemExit("fixture did not emit timeout records on at least three dates")
if not has_success:
    raise SystemExit("fixture did not emit successful submission records")
PY

echo "Setup complete: $APP is ready with application submission history available in its logs."
