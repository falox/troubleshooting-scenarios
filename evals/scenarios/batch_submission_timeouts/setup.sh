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
REGISTRY_ENDPOINT="127.0.0.1:${REGISTRY_LOCAL_PORT}"
PUSH_REGISTRY="$REGISTRY_ENDPOINT"
REGISTRY_PORT_FORWARD_ADDRESS="127.0.0.1"
REGISTRY_LOGIN_ARGS=()
if [ "$(uname -s)" = Darwin ]; then
  # Podman on macOS runs in a VM, so localhost is the VM, not the host.
  PUSH_REGISTRY="host.containers.internal:${REGISTRY_LOCAL_PORT}"
  REGISTRY_PORT_FORWARD_ADDRESS="0.0.0.0"
  REGISTRY_LOGIN_ARGS+=(--skip-check)
fi
REGISTRY_REPOSITORY="${NS}/${APP}"
CLUSTER_REGISTRY="image-registry.openshift-image-registry.svc:5000"
LOCAL_MANIFEST="${APP}-multiarch:${IMAGE_TAG}"
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

podman manifest rm "$LOCAL_MANIFEST" >/dev/null 2>&1 ||
  podman image rm "$LOCAL_MANIFEST" >/dev/null 2>&1 || true

echo "Building amd64/arm64 batch-processor image $LOCAL_MANIFEST..."
podman build \
  --platform linux/amd64,linux/arm64 \
  --manifest "$LOCAL_MANIFEST" \
  "$IMAGE_DIR"

echo "Starting internal registry port-forward..."
oc port-forward \
  --address "$REGISTRY_PORT_FORWARD_ADDRESS" \
  -n "$REGISTRY_NAMESPACE" \
  "service/$REGISTRY_SERVICE" \
  "${REGISTRY_LOCAL_PORT}:5000" >"$REGISTRY_LOG" 2>&1 &
REGISTRY_PORT_FORWARD_PID=$!

registry_ready=false
for _ in $(seq 1 30); do
  status_code="$(curl -k -sS -o /dev/null -w '%{http_code}' \
    --connect-timeout 2 --max-time 5 "https://${REGISTRY_ENDPOINT}/v2/" 2>/dev/null || true)"
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
  "${REGISTRY_LOGIN_ARGS[@]}" \
  --to="$AUTHFILE"

echo "Pushing multi-architecture batch-processor image to $PUSH_REGISTRY..."
podman manifest push \
  --authfile "$AUTHFILE" \
  --tls-verify=false \
  --all \
  --digestfile "$TMP_DIR/image.digest" \
  "$LOCAL_MANIFEST" \
  "docker://$PUSH_IMAGE"

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
