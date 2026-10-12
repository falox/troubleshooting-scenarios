"""Check pod selection, log names, and child process cleanup."""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "watch-logs"
SPEC = importlib.util.spec_from_file_location("sandbox_logs", SCRIPT.with_name("sandbox_logs.py"))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def pod(name, uid, run="test-run", step="analysis", state="running"):
    return {
        "metadata": {
            "name": name, "uid": uid,
            "labels": {MODULE.RUN_LABEL: "run-uid", MODULE.STEP_LABEL: step},
            "ownerReferences": [{
                "kind": "AgenticRun", "apiVersion": "agentic.openshift.io/v1alpha1",
                "name": run,
            }],
        },
        "status": {"containerStatuses": [{"name": "agent", "state": {state: {}}}]},
    }


class LogTests(unittest.TestCase):
    def test_owner_and_annotation_names(self):
        sample = pod("sandbox", "uid", step="verification")
        self.assertEqual(MODULE.log_stem(sample), "test-run-verification")
        sample["metadata"]["annotations"] = {MODULE.RUN_ANNOTATION: "annotation-run"}
        self.assertEqual(MODULE.log_stem(sample), "test-run-verification")
        del sample["metadata"]["ownerReferences"]
        self.assertEqual(MODULE.log_stem(sample), "annotation-run-verification")
        del sample["metadata"]["labels"][MODULE.STEP_LABEL]
        self.assertEqual(MODULE.log_stem(sample), "sandbox")

    def test_missing_run_uses_pod_name(self):
        sample = pod("sandbox", "uid")
        del sample["metadata"]["ownerReferences"]
        self.assertEqual(MODULE.log_stem(sample), "sandbox")

    def test_files_are_never_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "run-analysis.log").write_text("keep")
            (root / "run-analysis-1.log").write_text("keep too")
            path, output = MODULE.open_log(root, "run-analysis")
            with output:
                output.write(b"new")
            self.assertEqual(path.name, "run-analysis-2.log")
            self.assertEqual((root / "run-analysis.log").read_text(), "keep")
            self.assertEqual((root / "run-analysis-1.log").read_text(), "keep too")

    def test_reconnect_finds_new_pods_and_keeps_initial_pods_skipped(self):
        old = pod("old", "old-uid", state="waiting")
        new = pod("new", "new-uid")
        watcher = MODULE.Watcher(Path.cwd())
        watcher.follow = Mock()
        watcher.stop.wait = Mock()
        watcher.list_pods = Mock(side_effect=[
            {"metadata": {"resourceVersion": "123"}, "items": [old]},
            subprocess.CalledProcessError(1, "oc", stderr="Connection lost"),
            {"metadata": {"resourceVersion": "456"}, "items": [pod("old", "old-uid"), new]},
        ])
        watcher.watch = Mock(side_effect=[None, KeyboardInterrupt])
        with patch.object(MODULE, "report"):
            with self.assertRaises(KeyboardInterrupt):
                watcher.run()
        self.assertEqual([call.args[0] for call in watcher.watch.call_args_list], ["123", "456"])
        watcher.follow.assert_called_once_with(new)

    def test_readiness_is_signaled_after_initial_pods_are_recorded(self):
        ready = Mock()
        watcher = MODULE.Watcher(Path.cwd(), on_ready=ready)
        watcher.list_pods = Mock(return_value={
            "metadata": {"resourceVersion": "123"}, "items": [pod("old", "old-uid")],
        })

        def watch(version):
            self.assertEqual(version, "123")
            self.assertIn("old-uid", watcher.seen)
            ready.assert_called_once_with()
            raise KeyboardInterrupt

        watcher.watch = watch
        with patch.object(MODULE, "report"):
            with self.assertRaises(KeyboardInterrupt):
                watcher.run()

    def test_cli_watches_new_pods_and_stops_children(self):
        self.check_cli()

    def test_cli_creates_output_directory(self):
        for flag in ("-o", "--output-dir"):
            with self.subTest(flag=flag):
                self.check_cli(flag)

    def test_failed_login_stops_before_creating_output_or_watching(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "logs"
            with (
                patch.object(MODULE.shutil, "which", return_value="/usr/bin/oc"),
                patch.object(MODULE.subprocess, "run", side_effect=subprocess.CalledProcessError(
                    1, "oc", stderr="You must be logged in to the server"
                )) as command,
                patch.object(MODULE.Watcher, "run") as watch,
                patch.object(MODULE, "report") as report,
            ):
                self.assertEqual(MODULE.watch_logs(output), 1)
                self.assertEqual(command.call_args.args[0], ["oc", "whoami", "--request-timeout=10s"])
                watch.assert_not_called()
                self.assertIn("oc login", report.call_args.args[0])
                self.assertFalse(output.exists())

    def check_cli(self, output_flag=None):
        old = pod("old", "old-uid")
        pending = pod("pending", "pending-uid", state="waiting")
        first = pod("first", "first-uid")
        second = pod("second", "second-uid")
        execution = pod("execution", "execution-uid", step="execution", state="terminated")
        events = [
            {"type": "MODIFIED", "object": old},
            {"type": "ADDED", "object": pending},
            {"type": "ADDED", "object": first},
            {"type": "MODIFIED", "object": first},
            {"type": "ADDED", "object": second},
            {"type": "ADDED", "object": execution},
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "saved logs" / "nested" if output_flag else root
            (root / "initial.json").write_text(json.dumps({
                "metadata": {"resourceVersion": "123"}, "items": [old],
            }))
            (root / "events.json").write_text(json.dumps(events))
            (root / "test-run-analysis.log").write_text("keep")
            fake_oc = root / "oc"
            fake_oc.write_text(
                f"#!{sys.executable}\n"
                "import json, pathlib, sys, time\n"
                "root = pathlib.Path(__file__).parent\n"
                "args = sys.argv[1:]\n"
                "if args[0] == 'whoami':\n"
                "    (root / 'login-checked').touch()\n"
                "    print('test-user')\n"
                "elif args[:2] == ['get', 'pods']:\n"
                "    assert (root / 'login-checked').exists()\n"
                "    assert args[2:4] == ['-n', 'openshift-lightspeed']\n"
                "    print((root / 'initial.json').read_text())\n"
                "elif args[0] == 'get':\n"
                "    assert '/namespaces/openshift-lightspeed/pods?' in args[1]\n"
                "    assert 'resourceVersion=123' in args[1]\n"
                "    for event in json.loads((root / 'events.json').read_text()):\n"
                "        print(json.dumps(event), flush=True)\n"
                "    time.sleep(30)\n"
                "elif args[0] == 'logs':\n"
                "    assert args[1:3] == ['-n', 'openshift-lightspeed']\n"
                "    assert args[-3:] == ['-c', 'agent', '--follow']\n"
                "    print('log from ' + args[3], flush=True)\n"
                "    time.sleep(30)\n"
                "else:\n"
                "    sys.exit(2)\n"
            )
            fake_oc.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}{os.pathsep}{os.environ['PATH']}")
            command = [str(SCRIPT)]
            if output_flag:
                command.extend([output_flag, str(output.relative_to(root))])
            process = subprocess.Popen(
                command, cwd=root, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            try:
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    files = [path for path in output.glob("*.log") if path.read_text().startswith("log from")]
                    if len(files) == 3:
                        break
                    time.sleep(0.05)
                self.assertEqual(len(files), 3)
                self.assertEqual((root / "test-run-analysis.log").read_text(), "keep")
                if output_flag:
                    self.assertEqual(list(root.glob("*.log")), [root / "test-run-analysis.log"])
                self.assertEqual(
                    {path.name for path in files},
                    {"test-run-analysis.log" if output_flag else "test-run-analysis-2.log",
                     "test-run-analysis-1.log", "test-run-execution.log"},
                )
                self.assertEqual(
                    {path.read_text() for path in files},
                    {"log from first\n", "log from second\n", "log from execution\n"},
                )
            finally:
                process.terminate()
                try:
                    _, stderr = process.communicate(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.communicate()
                    self.fail("The watcher did not stop its child processes")
            self.assertEqual(process.returncode, 0, stderr)


if __name__ == "__main__":
    unittest.main()
