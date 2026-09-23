#!/usr/bin/env bash
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "$SCENARIO_DIR/../../../scripts" && pwd)"
NS="data-pipeline"
DELETE_TIMEOUT="${DELETE_TIMEOUT:-180}"

"$SCRIPTS_DIR/check-prerequisites.sh"

if ! [[ "$DELETE_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: DELETE_TIMEOUT must be a positive integer number of seconds" >&2
  exit 1
fi

if ! oc get namespace "$NS" >/dev/null 2>&1; then
  echo "Cleanup complete: namespace/$NS was already absent"
  exit 0
fi

echo "Deleting namespace/$NS..."
oc delete namespace "$NS" --ignore-not-found --wait=true --timeout="${DELETE_TIMEOUT}s"

for _ in $(seq 1 90); do
  if ! oc get namespace "$NS" >/dev/null 2>&1; then
    echo "Cleanup complete: namespace/$NS removed"
    exit 0
  fi
  sleep 2
done

echo "ERROR: namespace/$NS is still present after cleanup" >&2
exit 1
