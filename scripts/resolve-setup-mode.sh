#!/usr/bin/env bash
set -euo pipefail

# Use a fresh fault for each agent and repeat when remediation is selected.
mode="$1"
eval_file="$2"
shift 2

if [ "$mode" != auto ]; then
  printf '%s\n' "$mode"
  exit 0
fi

for scenario in "$@"; do
  if grep -q '^    - remediation$' "$scenario/$eval_file" 2>/dev/null; then
    echo run
    exit 0
  fi
done
echo scenario
