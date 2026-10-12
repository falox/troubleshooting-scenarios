"""Watch new sandbox pods in openshift-lightspeed and save their logs."""

import json
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
from pathlib import Path
from urllib.parse import urlencode


RUN_LABEL = "agentic.openshift.io/run"
STEP_LABEL = "agentic.openshift.io/step"
RUN_ANNOTATION = "agentic.openshift.io/run-name"
NAMESPACE = "openshift-lightspeed"


def log_stem(pod):
    """Use the run and step when both are known; otherwise use the pod name."""
    metadata = pod["metadata"]
    run = next(
        (
            owner["name"]
            for owner in metadata.get("ownerReferences", [])
            if owner.get("kind") == "AgenticRun"
            and owner.get("apiVersion", "").startswith("agentic.openshift.io/")
        ),
        metadata.get("annotations", {}).get(RUN_ANNOTATION),
    )
    step = metadata.get("labels", {}).get(STEP_LABEL)
    stem = f"{run}-{step}" if run and step else metadata["name"]
    return re.sub(r"[^A-Za-z0-9_.-]", "_", stem)


def open_log(directory, stem):
    """Reserve a file without replacing an existing log."""
    number = 0
    while True:
        suffix = f"-{number}" if number else ""
        path = directory / f"{stem}{suffix}.log"
        try:
            return path, path.open("xb")
        except FileExistsError:
            number += 1


def report(message):
    print(message, file=sys.stderr, flush=True)


class Watcher:
    def __init__(self, directory, on_ready=None):
        self.directory = directory
        self.on_ready = on_ready
        self.seen = set()
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.processes = set()
        self.threads = []

    def list_pods(self):
        result = subprocess.run(
            ["oc", "get", "pods", "-n", NAMESPACE, "-l", RUN_LABEL, "-o", "json",
             "--request-timeout=10s"],
            check=True, capture_output=True, text=True,
        )
        return json.loads(result.stdout)

    def handle(self, pod):
        metadata = pod["metadata"]
        uid = metadata["uid"]
        if uid in self.seen or RUN_LABEL not in metadata.get("labels", {}):
            return
        # Wait for the agent container, including pods that have already finished.
        statuses = pod.get("status", {}).get("containerStatuses", [])
        if not any(
            status["name"] == "agent"
            and ("running" in status.get("state", {}) or "terminated" in status.get("state", {}))
            for status in statuses
        ):
            return
        self.seen.add(uid)
        self.threads = [thread for thread in self.threads if thread.is_alive()]
        thread = threading.Thread(target=self.follow, args=(pod,))
        self.threads.append(thread)
        thread.start()

    def follow(self, pod):
        name = pod["metadata"]["name"]
        process = None
        try:
            path, output = open_log(self.directory, log_stem(pod))
            with output:
                report(f"{name} -> {path}")
                with self.lock:
                    if self.stop.is_set():
                        return
                    process = subprocess.Popen(
                        ["oc", "logs", "-n", NAMESPACE, name, "-c", "agent", "--follow"],
                        stdout=output, stderr=subprocess.PIPE,
                    )
                    self.processes.add(process)
                _, errors = process.communicate()
                if process.returncode and not self.stop.is_set():
                    report(f"Log stream failed for {name}: {errors.decode(errors='replace').strip()}")
                elif not self.stop.is_set():
                    report(f"Saved {path}")
        except OSError as error:
            report(f"Cannot save logs for {name}: {error}")
        finally:
            if process is not None:
                with self.lock:
                    self.processes.discard(process)

    def watch(self, resource_version):
        query = urlencode({
            "watch": "true", "resourceVersion": resource_version,
            "labelSelector": RUN_LABEL, "timeoutSeconds": "300",
        })
        url = f"/api/v1/namespaces/{NAMESPACE}/pods?{query}"
        with tempfile.TemporaryFile(mode="w+t") as errors:
            process = subprocess.Popen(
                ["oc", "get", f"--raw={url}"], stdout=subprocess.PIPE,
                stderr=errors, text=True,
            )
            try:
                for line in process.stdout:
                    event = json.loads(line)
                    if event["type"] in ("ADDED", "MODIFIED"):
                        self.handle(event["object"])
                    elif event["type"] == "ERROR":
                        report(f"Watch ended: {event['object'].get('message', 'API error')}")
                        break
                if process.poll() is not None and process.returncode:
                    errors.seek(0)
                    report(f"Watch failed: {errors.read().strip()}")
            finally:
                self.terminate(process)
                process.stdout.close()

    @staticmethod
    def terminate(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

    def run(self):
        try:
            initial = self.list_pods()
            self.seen.update(pod["metadata"]["uid"] for pod in initial["items"])
            resource_version = initial["metadata"]["resourceVersion"]
            # Let the eval runner start only after existing pods are recorded.
            if self.on_ready is not None:
                self.on_ready()
            report(f"Watching new sandbox pods in {NAMESPACE}. Press Ctrl+C to stop.")
            while not self.stop.is_set():
                try:
                    self.watch(resource_version)
                except (subprocess.CalledProcessError, OSError, ValueError) as error:
                    detail = getattr(error, "stderr", None) or str(error)
                    report(f"Cannot watch pods: {detail.strip()}")
                self.stop.wait(2)
                # Relist after a timeout or lost connection, then watch from that version.
                while not self.stop.is_set():
                    try:
                        pods = self.list_pods()
                        for pod in pods["items"]:
                            self.handle(pod)
                        resource_version = pods["metadata"]["resourceVersion"]
                        break
                    except (subprocess.CalledProcessError, OSError, ValueError) as error:
                        detail = getattr(error, "stderr", None) or str(error)
                        report(f"Cannot list pods: {detail.strip()}")
                        self.stop.wait(2)
        finally:
            self.stop.set()
            with self.lock:
                processes = list(self.processes)
            for process in processes:
                self.terminate(process)
            for thread in self.threads:
                thread.join()


def interrupt(*_):
    raise KeyboardInterrupt


def watch_logs(directory, on_ready=None):
    """Capture new sandbox pod logs until interrupted.

    Call on_ready after the initial pod list, before watching new events.
    Return zero on normal shutdown and one when startup fails.
    """
    if not shutil.which("oc"):
        report("oc must be installed and available in PATH")
        return 1
    try:
        subprocess.run(
            ["oc", "whoami", "--request-timeout=10s"],
            check=True, capture_output=True, text=True,
        )
    except (subprocess.CalledProcessError, OSError) as error:
        detail = getattr(error, "stderr", None) or str(error)
        report(f"Cannot verify oc login. Run 'oc login' and check cluster access.\n{detail.strip()}")
        return 1
    try:
        directory = Path(directory).expanduser().resolve()
        directory.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        report(f"Cannot use output directory: {error}")
        return 1
    previous_handler = signal.signal(signal.SIGTERM, interrupt)
    try:
        Watcher(directory, on_ready).run()
    except KeyboardInterrupt:
        report("Stopped.")
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        detail = getattr(error, "stderr", None) or str(error)
        report(f"Cannot start the watch: {detail.strip()}")
        return 1
    finally:
        signal.signal(signal.SIGTERM, previous_handler)
    return 0
