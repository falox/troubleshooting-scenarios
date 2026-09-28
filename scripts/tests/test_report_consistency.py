"""Check the shared scoring rules in both report generators."""

import importlib.util
from pathlib import Path

import pytest


@pytest.fixture(params=["classic", "agentic"])
def report_module(request):
    path = Path(__file__).resolve().parent.parent / f"generate-report-{request.param}.py"
    spec = importlib.util.spec_from_file_location(f"report_{request.param}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def metric(module, result, score, cid="scenario"):
    return {
        "conversation_group_id": cid,
        "metric_identifier": module.CORRECTNESS_METRIC,
        "result": result,
        "score": score,
    }


def test_errors_count_as_zero_in_cells_and_averages(report_module):
    mod = report_module
    runs = [
        [metric(mod, "PASS", 0.8), metric(mod, "ERROR", None, "other")],
        [metric(mod, "ERROR", None)],
        None,
    ]
    assert mod.overall_score(runs, ["scenario"]) == (1, 2)
    assert mod.scenario_mean_score(runs, "scenario") == pytest.approx(0.4)
    assert mod.mean_score(runs, ["scenario"]) == pytest.approx(0.4)
    assert mod.score_cell(runs, "scenario", "agent") == "[❌ 1/2](#agent--scenario) (0.40)"


def test_all_errors_have_zero_score(report_module):
    mod = report_module
    runs = [[metric(mod, "ERROR", 0.9)], [metric(mod, "ERROR", None)]]
    assert mod.overall_score(runs, ["scenario"]) == (0, 2)
    assert mod.mean_score(runs, ["scenario"]) == 0.0
    assert mod.score_cell(runs, "scenario", "agent") == "[❌ 0/2](#agent--scenario) (0.00)"


def test_missing_results_are_unavailable(report_module):
    mod = report_module
    runs = [None, []]
    assert mod.overall_score(runs, ["scenario"]) == (0, 0)
    assert mod.mean_score(runs, ["scenario"]) is None
    assert mod.score_cell(runs, "scenario", "agent") == "N/A"


def test_failed_completion_overrides_passing_correctness(report_module):
    mod = report_module
    status = metric(mod, "FAIL", 0.0)
    status["metric_identifier"] = "custom:openshift_agentic_run_status"
    runs = [[metric(mod, "PASS", 1.0), status]]
    assert mod.overall_score(runs, ["scenario"]) == (0, 1)
    assert mod.mean_score(runs, ["scenario"]) == 0.0


def test_model_order_follows_config(report_module, tmp_path):
    for name in ("alpha", "beta", "gamma", "extra"):
        (tmp_path / name / "run_1").mkdir(parents=True)
    config = tmp_path / "system.yaml"
    config.write_text("agents:\n  default:\n    agent: [gamma, missing, beta, gamma]\n")
    assert report_module.discover_agents(tmp_path, config) == [
        "gamma", "beta", "alpha", "extra",
    ]


def test_model_order_without_config_is_alphabetical(report_module, tmp_path):
    for name in ("beta", "alpha"):
        (tmp_path / name / "run_1").mkdir(parents=True)
    assert report_module.discover_agents(tmp_path, tmp_path / "missing.yaml") == [
        "alpha", "beta",
    ]


def test_score_medals_use_displayed_precision(report_module):
    mod = report_module
    runs = {
        name: [[metric(mod, "PASS", score)]]
        for name, score in (("first", 0.993), ("tied", 0.992), ("lower", 0.984))
    }
    names = list(runs)
    summary = mod.generate_summary_table(["scenario"], names, runs)
    average = next(line for line in summary.splitlines() if line.startswith("| **Avg score** |"))
    assert average == "| **Avg score** | **0.99** 🥇 | **0.99** 🥇 | 0.98 |"
    scenario = next(line for line in summary.splitlines() if line.startswith("| [scenario]"))
    assert scenario.count("🥇") == 2
    overview = mod.generate_overview_table(["scenario"], names, runs, {name: [] for name in names})
    assert "| Avg score | **0.99** 🥇 | **0.99** 🥇 | 0.98 |" in overview
