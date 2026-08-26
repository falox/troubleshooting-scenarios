#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="haystack"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for svc-charlie to exhibit CreateContainerConfigError..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 12 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=svc-charlie" \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || true)
  if echo "$STATE" | grep -q "CreateContainerConfigError"; then
    echo "svc-charlie is in CreateContainerConfigError"
    break
  fi
  sleep 5
done
if ! echo "$STATE" | grep -q "CreateContainerConfigError"; then
  echo "ERROR: svc-charlie did not reach CreateContainerConfigError within 60s"
  oc get pods -n "$NS" -o wide
  exit 1
fi

echo "Waiting for svc-echo to exhibit ImagePullBackOff..."
ATTEMPT=0
until [ "$ATTEMPT" -ge 12 ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATE=$(oc get pods -n "$NS" -l "app=svc-echo" \
    -o jsonpath='{.items[*].status.containerStatuses[*].state.waiting.reason}' 2>/dev/null || true)
  if echo "$STATE" | grep -Eq "ErrImagePull|ImagePullBackOff"; then
    echo "svc-echo is in ImagePullBackOff"
    break
  fi
  sleep 5
done
if ! echo "$STATE" | grep -Eq "ErrImagePull|ImagePullBackOff"; then
  echo "ERROR: svc-echo did not reach ImagePullBackOff within 60s"
  oc get pods -n "$NS" -o wide
  exit 1
fi

echo "Waiting for healthy workloads to become available..."
for deploy in svc-alpha svc-bravo svc-delta; do
  oc wait --for=condition=Available "deployment/$deploy" -n "$NS" --timeout=120s
done

echo "Setup complete: 3 healthy workloads, 2 broken"
