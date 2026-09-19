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
    echo "Error: scenario '$scenario' not found. Available scenarios:"
    for d in */; do
      if [ -f "${d}evals.yaml" ]; then echo "  ${d%/}"; fi
    done
    exit 1
  fi
done

DATETIME="$(date +%Y%m%d_%H%M%S)"
EVAL_DIR="results/logs/${DATETIME}"

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

if [ "$SETUP_MODE" = "run" ]; then
  for scenario in "${SCENARIOS[@]}"; do
    for agent in "${AGENTS[@]}"; do
      for run in $(seq 1 "$REPEAT"); do
        echo ""
        echo "==> Setup: $scenario"
        if [ -x "$scenario/setup.sh" ]; then bash "$scenario/setup.sh"; fi
        bash "$SCRIPT_DIR/run-agentic-evals.sh" \
          --system-config "$SYSTEM_CONFIG" \
          --evals "$scenario/evals.yaml" \
          --eval-dir "$EVAL_DIR" \
          --agent "$agent" \
          --run-index "$run" \
          "${TAG_FLAGS[@]}"
        echo "==> Cleanup: $scenario"
        if [ -x "$scenario/cleanup.sh" ]; then bash "$scenario/cleanup.sh" || echo "WARNING: cleanup failed (non-fatal)"; fi
      done
    done
  done
else
  for scenario in "${SCENARIOS[@]}"; do
    echo ""
    echo "==> Setup: $scenario"
    if [ -x "$scenario/setup.sh" ]; then bash "$scenario/setup.sh"; fi
    bash "$SCRIPT_DIR/run-agentic-evals.sh" \
      --system-config "$SYSTEM_CONFIG" \
      --evals "$scenario/evals.yaml" \
      --eval-dir "$EVAL_DIR" \
      "${TAG_FLAGS[@]}"
    echo "==> Cleanup: $scenario"
    if [ -x "$scenario/cleanup.sh" ]; then bash "$scenario/cleanup.sh" || echo "WARNING: cleanup failed (non-fatal)"; fi
  done
fi

echo ""
echo "==> Generating report..."
"$PYTHON" "$SCRIPT_DIR/generate-report-agentic.py" \
  "$EVAL_DIR" \
  --output "results/results_${DATETIME}.md"
echo "==> Results: results/results_${DATETIME}.md"
