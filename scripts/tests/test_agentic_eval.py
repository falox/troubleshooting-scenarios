"""Check that snapshots are frozen before the framework cleans up a run."""

import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace
from unittest.mock import patch

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agentic_crs

spec = importlib.util.spec_from_file_location(
    "agentic_eval", Path(__file__).resolve().parents[1] / "agentic-eval.py",
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_timeout_freezes_crs_before_cleanup_and_ignores_later_completion(tmp_path):
    run = {"kind": "AgenticRun", "metadata": {"name": "eval-one", "uid": "run-one", "resourceVersion": "1"}}
    result = {"kind": "VerificationResult", "metadata": {
        "name": "eval-one-verification-1", "uid": "result-one", "resourceVersion": "2",
        "labels": {agentic_crs.RUN_LABEL: "run-one"},
    }, "status": {"conditions": [{"type": "Started", "status": "True"}]}}

    class Driver:
        _config = SimpleNamespace(namespace="test-namespace")

        def _cleanup(self, name):
            assert name == "eval-one"
            assert yaml.safe_load((tmp_path / "verificationresult-eval-one-verification-1.yaml").read_text()) == result
            self.cleaned_up = True

        def execute_turn(self):
            self._cleanup("eval-one")
            return "Timeout after 900s for 'eval-one'", None

    module.install_snapshot_hook(Driver, tmp_path)
    driver = Driver()
    with patch.object(agentic_crs, "list_resources", return_value=[run, result]) as listing:
        assert driver.execute_turn() == ("Timeout after 900s for 'eval-one'", None)
    listing.assert_called_once_with("test-namespace")
    assert driver.cleaned_up
    stop = agentic_crs.saved_stops(tmp_path)["run-one"]
    assert stop["timed_out"] is True
    assert stop["stopped_at"]
    result["metadata"]["resourceVersion"] = "99"
    result["status"]["conditions"] = [{"type": "Completed", "status": "True", "reason": "Succeeded"}]
    agentic_crs.save_resource(tmp_path, result)
    saved = yaml.safe_load((tmp_path / "verificationresult-eval-one-verification-1.yaml").read_text())
    assert saved["status"]["conditions"][0]["type"] == "Started"
    # A result created only after eval stop is not part of that eval's evidence.
    result["kind"] = "EscalationResult"
    agentic_crs.save_resource(tmp_path, result)
    assert not list(tmp_path.glob("escalationresult-*.yaml"))


def test_snapshot_failure_preserves_the_eval_error_and_cleanup(tmp_path, capsys):
    class Driver:
        _config = SimpleNamespace(namespace="test-namespace")

        def _cleanup(self, name):
            self.cleaned_up = True

        def execute_turn(self):
            self._cleanup("eval-one")
            return "Timeout after 900s for 'eval-one'", None

    module.install_snapshot_hook(Driver, tmp_path)
    driver = Driver()
    with patch.object(module, "freeze_run", side_effect=OSError("connection lost")):
        assert driver.execute_turn() == ("Timeout after 900s for 'eval-one'", None)
    assert driver.cleaned_up
    assert "Cannot save CRs at eval stop" in capsys.readouterr().err
