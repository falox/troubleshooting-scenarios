"""Shared helpers for the Classic and Agentic evaluation reports."""

import json
from datetime import datetime
from pathlib import Path

import yaml

MEDAL = "🥇"
STATUS_METRIC = "custom:openshift_agentic_run_status"
CORRECTNESS_LEGEND = (
    "Legend: 🟢 100% pass rate · 🔴 0% pass rate · "
    "❌ Technical failure in at least one run (evaluation error or failed completion check)."
)


def has_technical_failure(results: list[dict], conversation_id: str) -> bool:
    """Check for an evaluation error or a failed completion check."""
    return any(
        metric["conversation_group_id"] == conversation_id
        and (
            metric["result"] == "ERROR"
            or (metric["metric_identifier"] == STATUS_METRIC and metric["result"] == "FAIL")
        )
        for metric in results
    )


def performance_result(
    results: list[dict], conversation_id: str, metric_ids: tuple[str, ...]
) -> tuple[str | None, float | None]:
    """Choose the first available metric; technical failures count as zero."""
    if has_technical_failure(results, conversation_id):
        return "ERROR", 0.0
    for metric_id in metric_ids:
        for metric in results:
            if (
                metric["conversation_group_id"] == conversation_id
                and metric["metric_identifier"] == metric_id
                and metric.get("result") is not None
            ):
                return metric["result"], metric.get("score")
    return None, None


def correctness_icon(passed: int, total: int, technical_failure: bool) -> str:
    if technical_failure:
        return "❌"
    return "🟢" if passed == total else ("🔴" if passed == 0 else "")


def winner_cell(text: str, is_winner: bool) -> str:
    """Format a winning cell with a medal marker."""
    return f"**{text}** {MEDAL}" if is_winner else text


def is_best_score(score: float | None, best: float | None) -> bool:
    """Award tied scores a medal using the displayed two decimal places."""
    return score is not None and best is not None and f"{score:.2f}" == f"{best:.2f}"


def discover_agents(eval_dir: Path, system_config: Path | None = None) -> list[str]:
    """List agents in config order, then unknown agents in alphabetical order."""
    agents = []
    for child in sorted(eval_dir.iterdir()):
        if child.is_dir() and any(child.glob("run_*")):
            agents.append(child.name)
    if system_config is None or not system_config.is_file():
        return agents
    config = yaml.safe_load(system_config.read_text()) or {}
    order = config.get("agents", {}).get("default", {}).get("agent", [])
    if isinstance(order, str):
        order = [order]
    ordered = list(dict.fromkeys(name for name in order if name in agents))
    return ordered + [name for name in agents if name not in ordered]


def find_run_dirs(eval_dir: Path, agent_name: str) -> list[Path]:
    """Find run_N directories for an agent, sorted by index."""
    agent_dir = eval_dir / agent_name
    if not agent_dir.is_dir():
        return []
    return sorted(agent_dir.glob("run_*"), key=lambda path: int(path.name.split("_")[1]))


def extract_judge_model(eval_dir: Path, agent_names: list[str]) -> str:
    """Extract the judge model name from the first available summary JSON."""
    for agent in agent_names:
        for run_dir in find_run_dirs(eval_dir, agent):
            for path in sorted(run_dir.glob("*_summary.json")):
                with path.open() as file:
                    data = json.load(file)
                config = data.get("configuration", {})
                judges = config.get("judge_panel", {}).get("judges", [])
                if not judges:
                    continue
                models = config.get("llm_pool", {}).get("models", {})
                model = models.get(judges[0], {}).get("model", "")
                if model:
                    return model
    return ""


def collect_conversations(agent_runs: dict[str, list]) -> list[str]:
    """Collect ordered unique conversation IDs across all agents and runs."""
    seen = set()
    conversations = []
    for runs in agent_runs.values():
        for results in runs:
            if results is None:
                continue
            for result in results:
                cid = result["conversation_group_id"]
                if cid not in seen:
                    seen.add(cid)
                    conversations.append(cid)
    return conversations


def anchor_id(agent: str, conversation_id: str) -> str:
    return f"{agent}--{conversation_id}"


def format_timestamp(timestamp: str) -> str:
    if not timestamp:
        return ""
    dt = datetime.fromisoformat(timestamp)
    return dt.strftime("%Y-%m-%d %H:%M:%S UTC")


def format_tokens_compact(number: int) -> str:
    if number >= 1_000_000:
        value = number / 1_000_000
        return f"{value:.1f}M".replace(".0M", "M")
    if number >= 1_000:
        value = number / 1_000
        return f"{value:.0f}K"
    return str(number)


def format_token_pair(input_tokens: int | None, output_tokens: int | None) -> str:
    if input_tokens is None and output_tokens is None:
        return "—"
    return (
        f"{format_tokens_compact(input_tokens or 0)}"
        f"/{format_tokens_compact(output_tokens or 0)}"
    )


def format_duration(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.0f}s"
    minutes = int(seconds // 60)
    remaining_seconds = int(seconds % 60)
    return f"{minutes}m {remaining_seconds}s"


def overall_score_cell(passed: int, total: int, bold: bool = False) -> str:
    if total == 0:
        return "N/A"
    percentage = round(100 * passed / total)
    return winner_cell(f"{percentage}% ({passed}/{total})", bold)


def scenario_tokens(
    agent_amended: list, conversation_id: str
) -> tuple[int | None, int | None]:
    """Return mean input/output tokens for one scenario across runs."""
    inputs = []
    outputs = []
    for entries in agent_amended:
        for entry in entries:
            if entry["conversation_group_id"] != conversation_id:
                continue
            input_tokens = entry.get("agent_input_tokens")
            output_tokens = entry.get("agent_output_tokens")
            if input_tokens is not None:
                inputs.append(input_tokens)
            if output_tokens is not None:
                outputs.append(output_tokens)
    mean_input = round(sum(inputs) / len(inputs)) if inputs else None
    mean_output = round(sum(outputs) / len(outputs)) if outputs else None
    return mean_input, mean_output


def mean_tokens(
    agent_amended: list, conversations: list[str]
) -> tuple[int | None, int | None]:
    """Return mean input/output tokens across runs and conversations."""
    inputs = []
    outputs = []
    for entries in agent_amended:
        for entry in entries:
            if entry["conversation_group_id"] not in conversations:
                continue
            input_tokens = entry.get("agent_input_tokens")
            output_tokens = entry.get("agent_output_tokens")
            if input_tokens is not None:
                inputs.append(input_tokens)
            if output_tokens is not None:
                outputs.append(output_tokens)
    mean_input = round(sum(inputs) / len(inputs)) if inputs else None
    mean_output = round(sum(outputs) / len(outputs)) if outputs else None
    return mean_input, mean_output


def format_report_metadata(
    report_type: str,
    timestamp: str,
    scenario_count: int,
    agent_count: int,
    repeat_count: int,
    judge: str,
    parallel_runs: bool = False,
) -> str:
    """Format the report type, dimensions, timestamp, and optional judge."""
    stats = (
        f"{scenario_count} scenario{'s' if scenario_count != 1 else ''}, "
        f"{agent_count} agent{'s' if agent_count != 1 else ''}, "
        f"{repeat_count} repeat{'s' if repeat_count > 1 else ''}"
    )
    if parallel_runs:
        stats += " (parallel)"
    parts = [timestamp] if timestamp else []
    parts.extend((f"**{report_type}**", stats))
    if judge:
        parts.append(f"Judge: {judge}")
    return " | ".join(parts)
