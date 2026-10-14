"""Check sandbox log capture during Agentic evaluations without a cluster."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

import pytest
import yaml


ROOT = Path(__file__).resolve().parents[2]


def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(0o755)


@pytest.fixture
def capture_workspace(tmp_path):
    root = tmp_path
    scripts = root / "scripts"
    scripts.mkdir()
    for name in (
        "eval-ols-agentic.sh", "sandbox_logs.py", "show-eval-summary.sh",
        "show-eval-summary.py", "eval-report.sh", "report_progress.py",
        "resolve-setup-mode.sh", "agentic_crs.py",
    ):
        shutil.copy(ROOT / "scripts" / name, scripts / name)
    shutil.copy(ROOT / "Makefile", root / "Makefile")
    executable(scripts / "preflight.sh", "#!/bin/bash\nexit 0\n")
    executable(root / "venv/bin/python3", f'#!/bin/bash\nexec "{sys.executable}" "$@"\n')
    (scripts / "generate-report-agentic.py").write_text(
        "from pathlib import Path\nimport sys\nPath(sys.argv[-1]).write_text('report\\n')\n"
    )
    scenario = root / "evals/scenarios/crashlooping_pod_alert"
    scenario.mkdir(parents=True)
    (scenario / "evals-ols-agentic.yaml").write_text("[]\n")
    (root / "evals/system-ols-agentic.yaml").write_text(yaml.safe_dump({
        "agents": {"default": {"agent": ["test-agent"], "repeat": 1}},
    }))
    sandbox = {
        "metadata": {
            "name": "ls-analysis-new", "uid": "new-pod",
            "labels": {"agentic.openshift.io/run": "new-run", "agentic.openshift.io/step": "analysis"},
            "ownerReferences": [{"name": "eval-new", "kind": "AgenticRun",
                                 "apiVersion": "agentic.openshift.io/v1alpha1"}],
        },
        "status": {"containerStatuses": [{"name": "agent", "state": {"running": {}}}]},
    }
    (root / "pod.json").write_text(json.dumps(sandbox))
    executable(root / "bin/oc", f"#!{sys.executable}\n" + '''
import json
import os
from pathlib import Path
import signal
import sys
import time

root = Path(os.environ["CAPTURE_ROOT"])
args = sys.argv[1:]
def stop(*_):
    (root / f"stopped-{os.getpid()}").touch()
    sys.exit(0)
signal.signal(signal.SIGTERM, stop)
(root / f"started-{os.getpid()}").touch()
if args[0] == "whoami":
    if os.environ.get("LOGIN_FAIL"):
        (root / f"stopped-{os.getpid()}").touch()
        sys.exit(7)
    print("test-user")
elif args[:2] == ["get", "pods"]:
    if os.environ.get("BASELINE_FAIL"):
        (root / f"stopped-{os.getpid()}").touch()
        sys.exit(9)
    # Give an evaluation started too early time to expose the startup race.
    time.sleep(0.3)
    assert not (root / "eval-trigger").exists(), "Eval started before the initial pod list"
    (root / "baseline-finished").touch()
    old = json.loads((root / "pod.json").read_text())
    old["metadata"]["uid"] = "old-pod"
    old["metadata"]["name"] = "ls-analysis-old"
    print(json.dumps({"metadata": {"resourceVersion": "123"}, "items": [old]}))
elif args[0] == "get" and not args[1].startswith("--raw="):
    print(json.dumps({"metadata": {"resourceVersion": "123"}, "items": []}))
elif args[0] == "get":
    assert "resourceVersion=123" in args[1]
    while not (root / "eval-trigger").exists():
        time.sleep(0.02)
    if "/pods?" in args[1]:
        obj = json.loads((root / "pod.json").read_text())
    else:
        kind = {"agenticruns": "AgenticRun", "analysisresults": "AnalysisResult",
                "executionresults": "ExecutionResult", "verificationresults": "VerificationResult",
                "escalationresults": "EscalationResult"}
        resource = args[1].split("?")[0].split("/")[-1]
        obj = {"kind": kind[resource], "metadata": {
            "name": "eval-new" if resource == "agenticruns" else f"eval-new-{resource}",
            "uid": "new-run" if resource == "agenticruns" else resource,
            "resourceVersion": "124", "labels": {"agentic.openshift.io/run": "new-run"}},
            "status": {"conditions": [{"type": "Completed", "status": "True", "reason": "Succeeded"}]}}
    print(json.dumps({"type": "ADDED", "object": obj}), flush=True)
    signal.pause()
elif args[0] == "logs":
    assert args[3] == "ls-analysis-new", "Existing pods must be skipped"
    print("sandbox evidence", flush=True)
    signal.pause()
else:
    sys.exit(8)
(root / f"stopped-{os.getpid()}").touch()
''')
    evaluator = root / "evaluator.py"
    evaluator.write_text('''
import os
from pathlib import Path
import signal
import sys
import time

root = Path(os.environ["CAPTURE_ROOT"])
args = sys.argv[1:]
session = Path(args[args.index("--eval-dir") + 1])
if not (os.environ.get("LOGIN_FAIL") or os.environ.get("BASELINE_FAIL")):
    assert (root / "baseline-finished").exists(), "Watcher must be ready before evaluation"
    (root / "eval-trigger").touch()
    log = session / "logs/eval-new-analysis.log"
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if log.exists() and log.read_text() == "sandbox evidence\\n":
            break
        time.sleep(0.02)
    assert log.read_text() == "sandbox evidence\\n"
output = session / "test-agent/run_1"
output.mkdir(parents=True, exist_ok=True)
(output / "raw.json").write_text('{"existing": true}\\n')
(session / "eval_report.json").write_text('{"existing": true}\\n')
if os.environ.get("INTERRUPT"):
    os.kill(os.getppid(), int(os.environ["INTERRUPT"]))
sys.exit(int(os.environ.get("EVAL_STATUS", "0")))
''')
    executable(scripts / "run-agentic-evals.sh", f'#!/bin/bash\nexec "{sys.executable}" "{evaluator}" "$@"\n')
    return root


def run_capture(root, make=False, **extra_env):
    env = {**os.environ, "CAPTURE_ROOT": str(root),
           "PATH": f"{root / 'bin'}:{os.environ['PATH']}", **extra_env}
    if make:
        command = ["make", "eval-ols-agentic", "SCENARIO=crashlooping_pod_alert", "SETUP_MODE=skip"]
        cwd = root
    else:
        command = ["bash", str(root / "scripts/eval-ols-agentic.sh"),
                   "--system-config", "system-ols-agentic.yaml", "--setup-mode", "skip",
                   "--scenarios", "scenarios/crashlooping_pod_alert"]
        cwd = root / "evals"
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=20)
    session = next((root / "evals/results").iterdir())
    assert not list(session.glob(".capture-logs-ready.*"))
    assert {path.name.replace("started-", "") for path in root.glob("started-*")} == {
        path.name.replace("stopped-", "") for path in root.glob("stopped-*")
    }
    assert (session / "test-agent/run_1/raw.json").read_text() == '{"existing": true}\n'
    assert (session / "eval_report.json").read_text() == '{"existing": true}\n'
    assert (session / "report.md").read_text() == "report\n"
    assert (session / "system-ols-agentic.yaml").is_file()
    assert (session / "scenarios/crashlooping_pod_alert/evals-ols-agentic.yaml").is_file()
    return result, session


def test_make_agentic_saves_sandbox_logs(capture_workspace):
    result, session = run_capture(capture_workspace, make=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert [path.name for path in (session / "logs").iterdir()] == ["eval-new-analysis.log"]
    assert (session / "logs/eval-new-analysis.log").read_text() == "sandbox evidence\n"
    assert "Stopped." in (session / "capture-logs.log").read_text()
    saved = [yaml.safe_load(path.read_text()) for path in (session / "crs").glob("*.yaml")]
    assert {cr["kind"] for cr in saved} == {
        "AgenticRun", "AnalysisResult", "ExecutionResult", "VerificationResult", "EscalationResult",
    }
    assert all(cr["status"]["conditions"][0]["reason"] == "Succeeded" for cr in saved)


@pytest.mark.parametrize("extra_env,exit_code", [
    ({"EVAL_STATUS": "42"}, 42),
    ({"INTERRUPT": "2"}, 130),
    ({"INTERRUPT": "15"}, 143),
])
def test_log_capture_stops_and_preserves_eval_status(capture_workspace, extra_env, exit_code):
    result, session = run_capture(capture_workspace, **extra_env)
    assert result.returncode == exit_code, result.stdout + result.stderr
    assert (session / "logs/eval-new-analysis.log").read_text() == "sandbox evidence\n"


@pytest.mark.parametrize("eval_status", ["0", "42"])
@pytest.mark.parametrize("failure", ["LOGIN_FAIL", "BASELINE_FAIL"])
def test_log_capture_startup_failure_keeps_eval_output(capture_workspace, eval_status, failure):
    result, session = run_capture(capture_workspace, **{failure: "1", "EVAL_STATUS": eval_status})
    assert result.returncode == int(eval_status), result.stdout + result.stderr
    assert "WARNING: sandbox log capture did not start" in result.stderr
    message = "Cannot verify oc login" if failure == "LOGIN_FAIL" else "Cannot start the watch"
    assert message in (session / "capture-logs.log").read_text()
    assert not list((session / "logs").iterdir())
