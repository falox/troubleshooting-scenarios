#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --system-config FILE [--setup-mode run|scenario] [--agents AGENT...] [--tags TAG...] --scenarios SCENARIO..."
  exit 1
}

SYSTEM_CONFIG=""
SCENARIOS=()
AGENTS=()
SETUP_MODE="run"
TAGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --system-config) SYSTEM_CONFIG="$2"; shift 2 ;;
    --setup-mode)    SETUP_MODE="$2"; shift 2 ;;
    --scenarios)     shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do SCENARIOS+=("$1"); shift; done ;;
    --agents)        shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do AGENTS+=("$1"); shift; done ;;
    --tags)          shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do TAGS+=("$1"); shift; done ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[ -n "$SYSTEM_CONFIG" ] && [ ${#SCENARIOS[@]} -gt 0 ] || usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/../venv"
PYTHON="${VENV_DIR}/bin/python3"

for scenario in "${SCENARIOS[@]}"; do
  if [ ! -d "$scenario" ]; then
    scenario_name="${scenario##*/}"
    echo "Error: scenario '$scenario_name' not found. Available scenarios:"
    echo ""
    available_scenarios=()
    for d in scenarios/*/; do
      scenario_name="${d%/}"
      if [ -f "${d}evals-ols-agentic.yaml" ]; then
        available_scenarios+=("${scenario_name##*/}")
      fi
    done

    if command -v column >/dev/null 2>&1; then
      terminal_width="${COLUMNS:-}"
      if ! [[ "$terminal_width" =~ ^[1-9][0-9]*$ ]]; then
        terminal_width="$(tput cols 2>/dev/null || true)"
      fi
      if [[ "$terminal_width" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s\n' "${available_scenarios[@]}" |
          column -x -c "$terminal_width" | expand | sed 's/^/  /'
      else
        printf '  %s\n' "${available_scenarios[@]}"
      fi
    else
      printf '  %s\n' "${available_scenarios[@]}"
    fi
    exit 64
  fi
done

DATETIME="$(date +%Y%m%d_%H%M%S)"
EVAL_DIR="results/${DATETIME}"

if [ ${#AGENTS[@]} -eq 0 ]; then
  read -ra AGENTS <<< "$("$PYTHON" -c "import yaml; c=yaml.safe_load(open('$SYSTEM_CONFIG')); print(' '.join(c.get('agents',{}).get('default',{}).get('agent',[])))")"
fi

REPEAT="$("$PYTHON" -c "import yaml; c=yaml.safe_load(open('$SYSTEM_CONFIG')); print(c.get('agents',{}).get('default',{}).get('repeat',1))")"

agent_description() {
  "$PYTHON" -c "
import yaml
c = yaml.safe_load(open('$SYSTEM_CONFIG'))
a = c.get('agents', {}).get('$1', {})
print(a.get('description', '') or '$1')
"
}

TAG_FLAGS=()
if [ ${#TAGS[@]} -gt 0 ]; then
  TAG_FLAGS=(--tags "${TAGS[@]}")
fi

echo "setup_mode: $SETUP_MODE"
echo "repeats:    $REPEAT"
echo "agents:     ${#AGENTS[@]}"
for agent in "${AGENTS[@]}"; do
  echo "  $(agent_description "$agent")"
done
echo "scenarios:  ${#SCENARIOS[@]}"
for scenario in "${SCENARIOS[@]}"; do
  echo "  $scenario"
done

run_scenario() {
  local scenario="$1"
  shift
  local scenario_status=0

  echo ""
  echo "==> Setup: $scenario"
  if [ -x "$scenario/setup.sh" ]; then bash "$scenario/setup.sh" || scenario_status=$?; fi
  if [ "$scenario_status" -eq 0 ]; then
    bash "$SCRIPT_DIR/run-agentic-evals.sh" \
      --system-config "$SYSTEM_CONFIG" \
      --evals "$scenario/evals-ols-agentic.yaml" \
      --eval-dir "$EVAL_DIR" \
      "$@" \
      "${TAG_FLAGS[@]}" || scenario_status=$?
  fi
  echo "==> Cleanup: $scenario"
  if [ -x "$scenario/cleanup.sh" ]; then bash "$scenario/cleanup.sh" || echo "WARNING: cleanup failed (non-fatal)"; fi
  return "$scenario_status"
}

if [ "$SETUP_MODE" = "run" ]; then
  for scenario in "${SCENARIOS[@]}"; do
    for agent in "${AGENTS[@]}"; do
      for run in $(seq 1 "$REPEAT"); do
        run_scenario "$scenario" \
          --agent "$agent" \
          --run-index "$run"
      done
    done
  done
else
  for scenario in "${SCENARIOS[@]}"; do
    run_scenario "$scenario"
  done
fi

echo ""
echo "==> Generating report..."
"$PYTHON" "$SCRIPT_DIR/generate-report-agentic.py" \
  "$EVAL_DIR" \
  --output "results/report_${DATETIME}.md"
echo "==> Report: results/report_${DATETIME}.md"
