#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="python3"
ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --python) PYTHON="$2"; shift 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if "$PYTHON" -c 'import yaml' >/dev/null 2>&1; then
  exec "$PYTHON" "$SCRIPT_DIR/show-eval-summary.py" "${ARGS[@]}"
fi

# Preview still works without Python or PyYAML. Config values need PyYAML.
SETUP_MODE=""
AGENTS=()
SCENARIOS=()
AGENTS_GIVEN=0
set -- "${ARGS[@]}"
while [ $# -gt 0 ]; do
  case "$1" in
    --system-config) shift 2 ;;
    --setup-mode) SETUP_MODE="$2"; shift 2 ;;
    --agents)
      AGENTS_GIVEN=1
      shift
      while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do AGENTS+=("$1"); shift; done
      ;;
    --scenarios)
      shift
      while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do SCENARIOS+=("$1"); shift; done
      ;;
    *) echo "ERROR: unknown summary option: $1" >&2; exit 2 ;;
  esac
done

echo "setup_mode: $SETUP_MODE"
echo "repeats:    (Python 3 and PyYAML needed for details)"
if [ "$AGENTS_GIVEN" -eq 1 ]; then
  echo "agents:     ${#AGENTS[@]}"
  printf '  %s\n' "${AGENTS[@]}"
else
  echo "agents:     (Python 3 and PyYAML needed for details)"
fi
echo "scenarios:  ${#SCENARIOS[@]}"
for scenario in "${SCENARIOS[@]}"; do
  echo "  ${scenario#scenarios/}"
done
if [ ${#SCENARIOS[@]} -eq 0 ]; then
  echo "No scenarios match the given filters."
fi
