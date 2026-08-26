#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="stuck-rollout"
APP="stuck-rollout-demo"

oc apply -f "$FIXTURE_DIR/deployment.yaml"

echo "Waiting for $APP to become available..."
oc wait --for=condition=Available "deployment/$APP" -n "$NS" --timeout=120s

echo "Rolling out a broken image to wedge the rollout..."
oc set image "deployment/$APP" \
  nginx=docker.io/nginxinc/nginx-unprivileged:9.99-broken -n "$NS"

echo "Waiting for the rollout to exceed its progress deadline..."
oc wait --for=condition=Progressing=false "deployment/$APP" \
  -n "$NS" --timeout=120s

echo "Setup complete: $APP rollout is stuck"
