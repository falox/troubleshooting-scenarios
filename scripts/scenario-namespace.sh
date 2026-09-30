#!/usr/bin/env bash

# Keep ownership outside the cluster so it does not reveal the scenario to an
# agent. Runners provide a separate directory for each setup/cleanup pair.
SCENARIO_STATE_DIR="${SCENARIO_STATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../evals" && pwd)/results/.scenario-state}"

scenario_create_namespace() {
  local namespace="$1"
  local manifest="$2"
  shift 2
  local state_file
  local status

  mkdir -p "$SCENARIO_STATE_DIR" || return $?
  state_file="$(mktemp "$SCENARIO_STATE_DIR/.namespace.XXXXXX")" || return $?
  # Record the UID returned by create itself. A failed create must not claim
  # an existing namespace, even when another process creates it during setup.
  if "$@" create -f "$manifest" -o jsonpath='{.metadata.uid}' >"$state_file"; then
    if [ ! -s "$state_file" ]; then
      echo "ERROR: namespace/$namespace creation returned no UID" >&2
      rm -f "$state_file"
      return 1
    fi
    mv "$state_file" "$SCENARIO_STATE_DIR/$namespace.uid"
  else
    status=$?
    rm -f "$state_file"
    return "$status"
  fi
}

scenario_namespace_owned() {
  local namespace="$1"
  shift
  local state_file="$SCENARIO_STATE_DIR/$namespace.uid"
  local current_uid
  local owned_uid

  if [ ! -s "$state_file" ]; then
    echo "Cleanup skipped: this setup did not create namespace/$namespace"
    return 1
  fi
  owned_uid="$(cat "$state_file")" || return 2
  current_uid="$("$@" get namespace "$namespace" --ignore-not-found -o jsonpath='{.metadata.uid}')" || return 2
  if [ -z "$current_uid" ]; then
    rm -f "$state_file"
    echo "Cleanup complete: namespace/$namespace was already absent"
    return 1
  fi
  if [ "$current_uid" != "$owned_uid" ]; then
    echo "Cleanup skipped: namespace/$namespace is not the namespace created by this setup"
    return 1
  fi
}
