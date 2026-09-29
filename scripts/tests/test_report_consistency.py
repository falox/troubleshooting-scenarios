"""Check the shared scoring rules in both report generators."""

import importlib.util
import json
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


def test_report_includes_saved_yaml_and_header_link(report_module, tmp_path):
    kind = Path(report_module.__file__).stem.removeprefix("generate-report-")
    content = "# Saved config, including a ``` fence\nagents:\n  default:\n    repeat: 7\n"
    (tmp_path / f"system-ols-{kind}.yaml").write_text(content)
    report = report_module.generate_report(tmp_path)
    assert "[System config](#system-config)" in report.splitlines()[2]
    assert '<a id="system-config"></a>' in report
    assert "````yaml\n" + content + "````" in report
    assert report.index("## Appendix: System config") > report.index("# Scenarios")


def test_report_does_not_use_current_yaml_for_old_sessions(report_module, tmp_path):
    report = report_module.generate_report(tmp_path)
    assert "The original YAML was not saved for this session." in report
    assert "```yaml" not in report


def test_scenario_names_use_directory_paths(report_module, tmp_path):
    filename = "evals-ols-classic.yaml"
    for directory, cid in (
        ("kiali-ossm/check_mesh_status", "check_mesh_status"),
        ("crashlooping_pod_alert", "crashlooping_pod"),
        ("first", "shared_id"),
        ("second", "shared_id"),
    ):
        path = tmp_path / directory / filename
        path.parent.mkdir(parents=True)
        path.write_text(f"- conversation_group_id: {cid}\n")
    (tmp_path / "first/evals-ols-agentic.yaml").write_text(
        "- conversation_group_id: check_mesh_status\n"
    )

    assert report_module.load_scenario_names(filename, tmp_path) == {
        "check_mesh_status": "kiali-ossm/check_mesh_status",
        "crashlooping_pod": "crashlooping_pod_alert",
    }


def test_directory_labels_keep_scores_and_links(
    report_module, tmp_path, monkeypatch, capsys,
):
    mod = report_module
    names = {"mesh_check": "kiali-ossm/check_mesh_status"}
    monkeypatch.setattr(mod, "load_scenario_names", lambda filename: names)
    results = [metric(mod, "PASS", 0.9, "mesh_check"), metric(mod, "FAIL", 0.2, "old_id")]
    for run in (1, 2):
        run_dir = tmp_path / f"agent/run_{run}"
        run_dir.mkdir(parents=True)
        (run_dir / "evaluation_summary.json").write_text(json.dumps({"results": results}))

    report = mod.generate_report(tmp_path)

    assert report.count("| [kiali-ossm/check_mesh_status](#mesh_check) |") == 3
    assert '<a id="mesh_check"></a>\n\n## kiali-ossm/check_mesh_status' in report
    assert '<a id="agent--mesh_check"></a>' in report
    assert "[🟢 2/2](#agent--mesh_check) (0.90)" in report
    assert "50% (2/4)" in report
    assert report.count("| [old_id](#old_id) |") == 3
    assert "## old_id\n" in report

    mod.print_correctness_table(
        ["mesh_check", "old_id"], ["agent"], {"agent": [results]}, scenario_names=names,
    )
    output = capsys.readouterr().out
    assert "kiali-ossm/check_mesh_status" in output
    assert "old_id" in output
    assert "50% (" in output
    # The longer directory label must fit in the CLI table.
    rows = [line for line in output.splitlines() if line.startswith("|")]
    assert len({line.index("|", 1) for line in rows}) == 1

    if hasattr(mod, "generate_phase_breakdown_table"):
        phases = mod.generate_phase_breakdown_table(
            ["mesh_check"], ["agent"], {"agent": [[]]}, scenario_names=names,
        )
        assert "| [kiali-ossm/check_mesh_status](#mesh_check) |" in phases
