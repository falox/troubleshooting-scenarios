#!/usr/bin/env bash
set -euo pipefail

FIXTURE_DIR="$(cd "$(dirname "$0")/fixtures" && pwd)"
NS="pvc-orphans"
APP="pvc-user-app"

# Guard: a default StorageClass is required for PVCs to bind.
if ! oc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{end}' | grep -q .; then
  echo "ERROR: no default StorageClass found — PVCs cannot bind."
  exit 1
fi

oc apply -f "$FIXTURE_DIR/manifest.yaml"

echo "Waiting for $APP deployment to become available..."
oc wait deployment "$APP" -n "$NS" --for=condition=Available --timeout=180s

echo "Setup complete: $APP is running with active-data-pvc bound; old-backup-pvc and tmp-scratch-pvc are orphaned"
