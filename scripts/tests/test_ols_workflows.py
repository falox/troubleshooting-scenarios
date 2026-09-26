"""Check OLS setup and failure handling without a cluster."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]
SYSTEM_CONFIG = yaml.safe_load((ROOT / "evals/system-ols-agentic.yaml").read_text())


def executable(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    path.chmod(0o755)


@pytest.fixture
def workspace(tmp_path):
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    for name in ("eval-ols-agentic.sh", "ci-ols-agentic-evals.sh", "sync-agent-crs.py"):
        shutil.copy(ROOT / "scripts" / name, scripts / name)
    evals = tmp_path / "evals"
    evals.mkdir()
    shutil.copy(ROOT / "Makefile", tmp_path / "Makefile")
    shutil.copy(ROOT / "evals/system-ols-agentic.yaml", evals / "system-ols-agentic.yaml")
    executable(
        tmp_path / "venv/bin/python3",
        f'#!/bin/bash\nexec "{sys.executable}" "$@"\n',
    )
    return tmp_path


@pytest.fixture
def classic_workspace(workspace):
    shutil.copy(ROOT / "scripts/eval-ols-classic.sh", workspace / "scripts/eval-ols-classic.sh")
    executable(workspace / "scripts/preflight.sh", "#!/bin/bash\nexit 0\n")
    executable(workspace / "bin/curl", "#!/bin/bash\nexit 0\n")
    executable(
        workspace / "bin/oc",
        '#!/bin/bash\nif [ "$1" = whoami ]; then echo test-token; fi\n',
    )
    (workspace / "evals/system-ols-classic.yaml").write_text("{}\n")
    (workspace / "scripts/generate-report-classic.py").write_text(
        'import os, sys\n'
        'with open(os.environ["EVENT_LOG"], "a") as f:\n'
        '    f.write("report\\n")\n'
        'with open(sys.argv[-1], "w") as f:\n'
        '    f.write("report\\n")\n'
    )
    return workspace


@pytest.mark.parametrize("mode", ["run", "scenario"])
@pytest.mark.parametrize(
    "setup_status,eval_status,cleanup_status,expected_status,events",
    [
        (23, 0, 0, 23, ["setup", "cleanup", "report"]),
        (0, 42, 0, 42, ["setup", "eval", "cleanup", "report"]),
        (0, 42, 9, 42, ["setup", "eval", "cleanup", "report"]),
        (0, 0, 9, 0, ["setup", "eval", "cleanup", "report"]),
        (0, 0, 0, 0, ["setup", "eval", "cleanup", "report"]),
    ],
)
def test_scenario_cleanup(
    workspace, mode, setup_status, eval_status, cleanup_status, expected_status, events
):
    (workspace / "evals/system-ols-agentic.yaml").write_text(yaml.safe_dump({
        "agents": {
            "default": {"repeat": 1},
            "openai-gpt-5-6-luna": {"description": "test|model"},
        }
    }))
    scenario = workspace / "evals/scenarios/sample"
    for name, status in (("setup", setup_status), ("cleanup", cleanup_status)):
        executable(
            scenario / f"{name}.sh",
            f'#!/bin/bash\necho {name} >> "$EVENT_LOG"\nexit {status}\n',
        )
    executable(
        workspace / "scripts/run-agentic-evals.sh",
        f'#!/bin/bash\necho eval >> "$EVENT_LOG"\nexit {eval_status}\n',
    )
    (workspace / "scripts/generate-report-agentic.py").write_text(
        'import os\nwith open(os.environ["EVENT_LOG"], "a") as f:\n'
        '    f.write("report\\n")\n'
    )
    log = workspace / "events"
    result = subprocess.run(
        [
            "bash", str(workspace / "scripts/eval-ols-agentic.sh"),
            "--system-config", "system-ols-agentic.yaml",
            "--setup-mode", mode, "--agents", "openai-gpt-5-6-luna",
            "--scenarios", "scenarios/sample",
        ],
        cwd=workspace / "evals",
        env={**os.environ, "EVENT_LOG": str(log)},
        capture_output=True, text=True,
    )
    assert result.returncode == expected_status, result.stdout + result.stderr
    assert log.read_text().splitlines() == events


@pytest.mark.parametrize("mode", ["run", "scenario"])
@pytest.mark.parametrize("failure_step,expected_status", [("setup", 23), ("eval", 42)])
def test_failed_scenario_allows_later_scenarios_and_report(
    workspace, mode, failure_step, expected_status
):
    (workspace / "evals/system-ols-agentic.yaml").write_text(yaml.safe_dump({
        "agents": {
            "default": {"repeat": 1},
            "test-agent": {"description": "Test agent"},
        }
    }))
    for name in ("first", "second"):
        scenario = workspace / "evals/scenarios" / name
        setup_status = 23 if name == "first" and failure_step == "setup" else 0
        executable(
            scenario / "setup.sh",
            f'#!/bin/bash\necho setup:{name} >> "$EVENT_LOG"\nexit {setup_status}\n',
        )
        executable(
            scenario / "cleanup.sh",
            f'#!/bin/bash\necho cleanup:{name} >> "$EVENT_LOG"\n',
        )
        (scenario / "evals-ols-agentic.yaml").write_text("[]\n")

    executable(
        workspace / "scripts/run-agentic-evals.sh",
        '#!/bin/bash\n'
        'scenario="$(basename "$(dirname "$4")")"\n'
        'echo "eval:$scenario" >> "$EVENT_LOG"\n'
        'if [ "$scenario" = first ] && [ "$FAILURE_STEP" = eval ]; then exit 42; fi\n',
    )
    (workspace / "scripts/generate-report-agentic.py").write_text(
        'import os, sys\n'
        'with open(os.environ["EVENT_LOG"], "a") as f:\n'
        '    f.write("report\\n")\n'
        'with open(sys.argv[-1], "w") as f:\n'
        '    f.write("report\\n")\n'
    )
    log = workspace / "events"
    result = subprocess.run(
        [
            "bash", str(workspace / "scripts/eval-ols-agentic.sh"),
            "--system-config", "system-ols-agentic.yaml",
            "--setup-mode", mode, "--agents", "test-agent",
            "--tags", "alert",
            "--scenarios", "scenarios/first", "scenarios/second",
        ],
        cwd=workspace / "evals",
        env={**os.environ, "EVENT_LOG": str(log), "FAILURE_STEP": failure_step},
        capture_output=True, text=True,
    )
    assert result.returncode == expected_status, result.stdout + result.stderr
    expected_events = ["setup:first"]
    if failure_step == "eval":
        expected_events.append("eval:first")
    expected_events += [
        "cleanup:first", "setup:second", "eval:second", "cleanup:second", "report",
    ]
    assert log.read_text().splitlines() == expected_events
    assert list((workspace / "evals/results").glob("report_*.md"))


@pytest.mark.parametrize("failure_step,expected_status", [("setup", 23), ("eval", 42)])
def test_classic_failed_scenario_allows_later_scenarios_and_report(
    classic_workspace, failure_step, expected_status
):
    for name in ("first", "second"):
        scenario = classic_workspace / "evals/scenarios" / name
        setup_status = 23 if name == "first" and failure_step == "setup" else 0
        executable(
            scenario / "setup.sh",
            f'#!/bin/bash\necho setup:{name} >> "$EVENT_LOG"\nexit {setup_status}\n',
        )
        executable(
            scenario / "cleanup.sh",
            f'#!/bin/bash\necho cleanup:{name} >> "$EVENT_LOG"\n',
        )
        (scenario / "evals-ols-classic.yaml").write_text("[]\n")

    executable(
        classic_workspace / "scripts/run-agentic-evals.sh",
        '#!/bin/bash\n'
        'scenario="$(basename "$(dirname "$4")")"\n'
        'echo "eval:$scenario" >> "$EVENT_LOG"\n'
        'if [ "$scenario" = first ] && [ "$FAILURE_STEP" = eval ]; then exit 42; fi\n',
    )
    log = classic_workspace / "events"
    result = subprocess.run(
        [
            "bash", str(classic_workspace / "scripts/eval-ols-classic.sh"),
            "--system-config", "system-ols-classic.yaml",
            "--tags", "alert",
            "--scenarios", "scenarios/first", "scenarios/second",
        ],
        cwd=classic_workspace / "evals",
        env={
            **os.environ,
            "PATH": f"{classic_workspace / 'bin'}:{os.environ['PATH']}",
            "EVENT_LOG": str(log),
            "FAILURE_STEP": failure_step,
        },
        capture_output=True, text=True,
    )
    assert result.returncode == expected_status, result.stdout + result.stderr
    expected_events = ["setup:first"]
    if failure_step == "eval":
        expected_events.append("eval:first")
    expected_events += [
        "cleanup:first", "setup:second", "eval:second", "cleanup:second", "report",
    ]
    assert log.read_text().splitlines() == expected_events
    assert list((classic_workspace / "evals/results").glob("report_*.md"))


def test_classic_failed_group_setup_skips_group_and_reports_other_scenarios(
    classic_workspace,
):
    group = classic_workspace / "evals/scenarios/group"
    executable(
        group / "setup.sh",
        '#!/bin/bash\necho group-setup >> "$EVENT_LOG"\nexit 31\n',
    )
    executable(
        group / "cleanup.sh",
        '#!/bin/bash\necho group-cleanup >> "$EVENT_LOG"\n',
    )
    for name in ("group/first", "group/second", "other/third"):
        scenario = classic_workspace / "evals/scenarios" / name
        executable(
            scenario / "setup.sh",
            f'#!/bin/bash\necho setup:{name} >> "$EVENT_LOG"\n',
        )
        executable(
            scenario / "cleanup.sh",
            f'#!/bin/bash\necho cleanup:{name} >> "$EVENT_LOG"\n',
        )
        (scenario / "evals-ols-classic.yaml").write_text("[]\n")

    executable(
        classic_workspace / "scripts/run-agentic-evals.sh",
        '#!/bin/bash\necho eval >> "$EVENT_LOG"\n',
    )
    log = classic_workspace / "events"
    result = subprocess.run(
        [
            "bash", str(classic_workspace / "scripts/eval-ols-classic.sh"),
            "--system-config", "system-ols-classic.yaml",
            "--scenarios", "scenarios/group/first", "scenarios/group/second",
            "scenarios/other/third",
        ],
        cwd=classic_workspace / "evals",
        env={
            **os.environ,
            "PATH": f"{classic_workspace / 'bin'}:{os.environ['PATH']}",
            "EVENT_LOG": str(log),
        },
        capture_output=True, text=True,
    )
    assert result.returncode == 31, result.stdout + result.stderr
    assert log.read_text().splitlines() == [
        "group-setup", "setup:other/third", "eval", "cleanup:other/third",
        "group-cleanup", "report",
    ]
    assert "Skipping scenarios/group/second" in result.stderr
    assert list((classic_workspace / "evals/results").glob("report_*.md"))


@pytest.mark.parametrize("variant", ["classic", "agentic"])
def test_setup_dependencies(variant):
    result = subprocess.run(
        ["make", "--dry-run", f"setup-ols-{variant}"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    assert result.stdout.count("setup-venv.sh") == 1
    assert ("sync-agent-crs.py" in result.stdout) == (variant == "agentic")
    assert ("setup-ols.sh" in result.stdout) == (variant == "classic")


@pytest.mark.parametrize("agent", [None, *SYSTEM_CONFIG["agents"]["default"]["agent"], "invalid"])
def test_ci_agent_provisioning(workspace, agent):
    bin_dir = workspace / "bin"
    executable(
        bin_dir / "git",
        '#!/bin/bash\nmkdir -p "${@: -1}/hack/quickstart"\n'
        'touch "${@: -1}/hack/quickstart/install.sh"\n',
    )
    executable(
        bin_dir / "oc",
        f"#!{sys.executable}\n"
        "import os, sys, yaml, json\n"
        "if sys.argv[1] == 'apply':\n"
        "    state_path = os.environ['CR_STATE']\n"
        "    try:\n"
        "        with open(state_path) as f: resources = json.load(f)\n"
        "    except FileNotFoundError:\n"
        "        resources = []\n"
        "    with open(os.environ['CR_LOG'], 'a') as f:\n"
        "        for doc in yaml.safe_load_all(sys.stdin):\n"
        "            if doc:\n"
        "                f.write(json.dumps(doc) + '\\n')\n"
        "                resources = [r for r in resources if not (\n"
        "                    r.get('kind') == doc.get('kind') and\n"
        "                    r.get('metadata', {}).get('name') == doc.get('metadata', {}).get('name') and\n"
        "                    r.get('metadata', {}).get('namespace') == doc.get('metadata', {}).get('namespace')\n"
        "                )]\n"
        "                resources.append(doc)\n"
        "    with open(state_path, 'w') as f: json.dump(resources, f)\n"
        "elif sys.argv[1] == 'get':\n"
        "    try:\n"
        "        with open(os.environ['CR_STATE']) as f: resources = json.load(f)\n"
        "    except FileNotFoundError:\n"
        "        resources = []\n"
        "    print(json.dumps({'items': [r for r in resources if r.get('kind') == 'Agent']}))\n",
    )
    executable(
        workspace / "scripts/setup-venv.sh", "#!/bin/bash\nexit 0\n"
    )
    executable(
        bin_dir / "make",
        '#!/bin/bash\nprintf "%s\\n" "$*" >> "$MAKE_LOG"\n'
        'if [ "$1" = setup-ols-agentic ]; then\n'
        f'  exec "{shutil.which("make")}" "$@"\n'
        'fi\n',
    )
    credentials = workspace / "credentials.json"
    credentials.write_text('{"project_id": "test-project"}')
    env = {
        **os.environ,
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "OPENAI_API_KEY": "test-key",
        "GOOGLE_APPLICATION_CREDENTIALS": str(credentials),
        "VERTEX_PROJECT_ID": "test-project",
        "ARTIFACT_DIR": str(workspace / "artifacts"),
        "MAKE_LOG": str(workspace / "make.log"),
        "CR_LOG": str(workspace / "cr.log"),
        "CR_STATE": str(workspace / "cr-state.json"),
    }
    env.pop("AGENT", None)
    if agent is not None:
        env["AGENT"] = agent
    result = subprocess.run(
        ["bash", str(workspace / "scripts/ci-ols-agentic-evals.sh")],
        env=env, capture_output=True, text=True,
    )
    if agent == "invalid":
        assert result.returncode == 1
        assert "Unknown AGENT=invalid" in result.stderr
        assert not (workspace / "make.log").exists()
        assert not (workspace / "cr.log").exists()
        return

    assert result.returncode == 0, result.stdout + result.stderr
    selected = agent or SYSTEM_CONFIG["agents"]["default"]["agent"][0]
    config = SYSTEM_CONFIG["agents"][selected]
    provider, model = config["description"].split("|", 1)
    resources = [json.loads(line) for line in (workspace / "cr.log").read_text().splitlines()]
    providers = [r for r in resources if r["kind"] == "LLMProvider"]
    assert [r["metadata"]["name"] for r in providers] == [provider]
    agent_cr = next(
        r for r in resources
        if r["kind"] == "Agent" and r["metadata"]["name"] == config["agent_ref"]
    )
    assert agent_cr["spec"]["llmProvider"]["name"] == provider
    assert agent_cr["spec"]["model"] == model
    assert f"eval-ols-agentic AGENT={selected}" in (workspace / "make.log").read_text()
