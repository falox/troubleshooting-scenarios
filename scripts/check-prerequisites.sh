#!/usr/bin/env bash
set -euo pipefail

if ! command -v oc &>/dev/null; then
  echo "ERROR: 'oc' command not found. Install the OpenShift CLI first." >&2
  exit 1
fi

if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged in to an OpenShift cluster. Run 'oc login' first." >&2
  exit 1
fi
