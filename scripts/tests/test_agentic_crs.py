"""Check CR capture and exact run matching without cluster access."""

import io
import json
from pathlib import Path
import sys
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agentic_crs as crs


def run(name="eval-one", uid="run-one", agent="model", created="2026-10-13T10:00:00Z"):
    return {"kind": "AgenticRun", "metadata": {
        "name": name, "uid": uid, "creationTimestamp": created, "resourceVersion": "2",
    }, "spec": {"request": "Investigate the alert", "analysis": {"agent": agent}},
        "status": {"conditions": []}}


def result(kind="AnalysisResult", uid="run-one", reason="Succeeded"):
    return {"kind": kind, "metadata": {
        "name": "eval-one-analysis-1", "uid": "result-one", "resourceVersion": "3",
        "ownerReferences": [{"kind": "AgenticRun", "apiVersion": "agentic.openshift.io/v1alpha1",
                             "name": "eval-one", "uid": uid}],
    }, "status": {"conditions": [{"type": "Completed", "status": "True", "reason": reason}]}}


def test_capture_excludes_existing_runs_and_unrelated_kinds(tmp_path):
    capture = crs.CRCapture(tmp_path, Mock())
    capture.initial_runs = {"old-run"}
    with patch.object(crs, "list_resources", return_value=[
        run(uid="old-run"), result(uid="old-run"), run(), result(),
        {"kind": "Agent", "metadata": {"name": "model", "uid": "agent"}},
        {"kind": "LLMProvider", "metadata": {"name": "provider", "uid": "provider"}},
    ]):
        capture.refresh()
    saved = [json.loads(path.read_text()) for path in tmp_path.glob("*.json")]
    assert {cr["kind"] for cr in saved} == {"AgenticRun", "AnalysisResult"}
    assert {crs.run_owner(cr) for cr in saved} == {"run-one"}


def test_watch_keeps_deleted_results(tmp_path):
    capture = crs.CRCapture(tmp_path, Mock())
    resource = result()
    process = Mock()
    process.stdout = io.StringIO(json.dumps({"type": "DELETED", "object": resource}) + "\n")
    original_handle = capture.handle

    def handle(cr):
        original_handle(cr)
        capture.stop_event.set()

    capture.handle = handle
    with patch.object(crs.subprocess, "Popen", return_value=process):
        capture.watch("analysisresults", "1")
    assert json.loads(next(tmp_path.glob("*.json")).read_text()) == resource


def test_newer_status_is_not_overwritten_and_reused_names_keep_both_uids(tmp_path):
    resource = result()
    crs.save_resource(tmp_path, resource)
    older = result(reason="Failed")
    older["metadata"]["resourceVersion"] = "2"
    crs.save_resource(tmp_path, older)
    assert json.loads(next(tmp_path.glob("*.json")).read_text()) == resource
    reused = result(reason="Failed")
    reused["metadata"]["uid"] = "new-result"
    crs.save_resource(tmp_path, reused)
    assert len(list(tmp_path.glob("*.json"))) == 2


def test_recovery_only_saves_logged_runs_and_their_children(tmp_path):
    (tmp_path / "logs").mkdir()
    (tmp_path / "logs/eval-one-analysis.log").touch()
    with patch.object(crs, "list_resources", return_value=[
        run(), result(), run("eval-other", "other"), result(uid="other"),
    ]):
        assert crs.recover(tmp_path, set()) == 2
    assert len(list((tmp_path / "crs").glob("*.json"))) == 2


def test_timeout_name_matches_the_exact_run_and_owner_uid(tmp_path):
    for resource in [run(), run("eval-two", "run-two"), result(), result("VerificationResult", "run-two")]:
        crs.save_resource(tmp_path / "crs", resource)
    entries = [{"conversation_group_id": "scenario", "agentic_run_status": {},
                "query": "Investigate the alert", "turn_id": "turn_1"}]
    crs.SavedCRs(tmp_path).enrich(entries, "model", 1, [{
        "conversation_group_id": "scenario", "turn_id": "turn_1",
        "reason": "Timeout after 600s for 'eval-two'",
    }])
    assert entries[0]["agentic_run_cr"]["metadata"]["uid"] == "run-two"
    assert set(entries[0]["agentic_run_results"]) == {"verification"}


def test_repeats_with_the_same_request_keep_their_own_crs(tmp_path):
    for resource in [run("eval-two", "run-two", created="2026-10-13T10:01:00Z"), run()]:
        crs.save_resource(tmp_path / "crs", resource)
    saved = crs.SavedCRs(tmp_path)
    for index, uid in [(1, "run-one"), (2, "run-two")]:
        entries = [{"conversation_group_id": "scenario", "agentic_run_status": {},
                    "query": "Investigate the alert"}]
        saved.enrich(entries, "model", index, [])
        assert entries[0]["agentic_run_cr"]["metadata"]["uid"] == uid


def test_initial_list_failure_does_not_capture_old_runs(tmp_path):
    report = Mock()
    capture = crs.CRCapture(tmp_path, report)
    with patch.object(crs.subprocess, "run", side_effect=OSError("connection lost")):
        capture.start()
        capture.stop()
    report.assert_called_once()
    assert not list(tmp_path.glob("*.json"))
