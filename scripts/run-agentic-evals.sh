#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --system-config FILE --evals FILE --eval-dir DIR [--agent AGENT --run-index N] [--tags TAG ...]"
  echo ""
  echo "  --eval-dir DIR        Target directory for results ({agent}/run_{N}/ structure)"
  echo "  --agent AGENT         Run only this agent with repeat=1 (creates temp config)"
  echo "  --run-index N         Place output in run_N/ instead of run_1/ (requires --agent)"
  exit 1
}

SYSTEM_CONFIG=""
EVALS=""
EVAL_DIR=""
AGENT=""
RUN_INDEX=""
TAGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --system-config) SYSTEM_CONFIG="$2"; shift 2 ;;
    --evals)         EVALS="$2"; shift 2 ;;
    --eval-dir)      EVAL_DIR="$2"; shift 2 ;;
    --agent)         AGENT="$2"; shift 2 ;;
    --run-index)     RUN_INDEX="$2"; shift 2 ;;
    --tags)          shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do TAGS+=("$1"); shift; done ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

[ -n "$SYSTEM_CONFIG" ] && [ -n "$EVALS" ] && [ -n "$EVAL_DIR" ] || usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/../venv"

if [ ! -f "${VENV_DIR}/bin/lightspeed-eval" ]; then
  echo "ERROR: lightspeed-eval not found at ${VENV_DIR}/bin/lightspeed-eval"
  echo "Run setup first (make setup)"
  exit 1
fi

if [ -z "${OPENAI_API_KEY:-}" ]; then
  printf '\033[0;31mERROR:\033[0m OPENAI_API_KEY not set (needed for judge LLM)\n'
  exit 1
fi

TAG_FLAGS=()
if [ ${#TAGS[@]} -gt 0 ]; then
  TAG_FLAGS=(--tags "${TAGS[@]}")
fi

RUNTIME_CONFIG="$SYSTEM_CONFIG"
cleanup_runtime() {
  if [ "$RUNTIME_CONFIG" != "$SYSTEM_CONFIG" ]; then
    rm -f "$RUNTIME_CONFIG"
  fi
}
trap cleanup_runtime EXIT

if [ -n "$AGENT" ]; then
  # Single-agent mode: create temp config with just this agent and repeat=1
  RUNTIME_CONFIG="$(mktemp)"
  "${VENV_DIR}/bin/python3" -c "
import yaml, sys
with open('$SYSTEM_CONFIG') as f:
    cfg = yaml.safe_load(f)
cfg['agents']['default']['agent'] = ['$AGENT']
cfg['agents']['default']['repeat'] = 1
cfg['agents']['default']['parallel'] = False
yaml.dump(cfg, sys.stdout, default_flow_style=False)
" > "$RUNTIME_CONFIG"
fi

TMPDIR_EVAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_EVAL"; cleanup_runtime' EXIT

echo ""
if [ -n "$AGENT" ]; then
  echo "==> Eval: agent=$AGENT${RUN_INDEX:+ run=$RUN_INDEX} evals=$(basename "$EVALS")"
else
  echo "==> Eval: evals=$(basename "$EVALS")"
fi

"${VENV_DIR}/bin/lightspeed-eval" \
  --system-config "$RUNTIME_CONFIG" \
  --output-dir "$TMPDIR_EVAL" \
  --eval-data "$EVALS" \
  "${TAG_FLAGS[@]}"

# Move output from the orchestrator's eval_* structure to the target eval-dir.
# Orchestrator creates: $TMPDIR_EVAL/eval_{ts}/{agent}/run_{N}/
# We want:              $EVAL_DIR/{agent}/run_{N}/
eval_subdir="$(find "$TMPDIR_EVAL" -maxdepth 1 -name 'eval_*' -type d | head -1)"
if [ -z "$eval_subdir" ]; then
  echo "WARNING: No eval output produced (filter may have matched nothing)"
  exit 0
fi

if [ -n "$AGENT" ] && [ -n "$RUN_INDEX" ]; then
  # Single-agent mode: rename run_1 to run_$RUN_INDEX
  src="$eval_subdir/$AGENT/run_1"
  dest="$EVAL_DIR/$AGENT/run_${RUN_INDEX}"
  if [ -d "$src" ]; then
    mkdir -p "$dest"
    cp -a "$src"/. "$dest"/
  fi
else
  # Multi-agent mode: copy the whole agent/run structure
  for agent_dir in "$eval_subdir"/*/; do
    [ -d "$agent_dir" ] || continue
    agent_name="$(basename "$agent_dir")"
    for run_dir in "$agent_dir"/run_*/; do
      [ -d "$run_dir" ] || continue
      run_name="$(basename "$run_dir")"
      dest="$EVAL_DIR/$agent_name/$run_name"
      mkdir -p "$dest"
      cp -a "$run_dir"/. "$dest"/
    done
  done
fi

# Copy eval_report.json if present (from multi-agent orchestrator runs)
if [ -f "$eval_subdir/eval_report.json" ]; then
  cp "$eval_subdir/eval_report.json" "$EVAL_DIR/"
fi
