"""Save AgenticRun and result CRs, and read them without cluster access."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import json
from pathlib import Path
import re
import subprocess
import sys
import threading
from urllib.parse import urlencode

import yaml

from report_progress import write_atomic


NAMESPACE = "openshift-lightspeed"
RUN_LABEL = "agentic.openshift.io/run"
RESULT_KINDS = {
    "AnalysisResult": "analysis", "ExecutionResult": "execution",
    "VerificationResult": "verification", "EscalationResult": "escalation",
}
RESOURCES = "agenticruns,analysisresults,executionresults,verificationresults,escalationresults"
STOPS_FILE = "eval-stops.json"


@contextmanager
def snapshot_lock(directory):
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / ".capture.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def saved_stops(directory):
    path = directory / STOPS_FILE
    return json.loads(path.read_text()) if path.exists() else {}


def run_owner(resource):
    """Use the parent UID to avoid mixing runs with the same name."""
    if resource.get("kind") == "AgenticRun":
        return resource.get("metadata", {}).get("uid")
    metadata = resource.get("metadata", {})
    return next((owner.get("uid") for owner in metadata.get("ownerReferences", []) or []
                 if owner.get("kind") == "AgenticRun"
                 and owner.get("apiVersion", "").startswith("agentic.openshift.io/")),
                metadata.get("labels", {}).get(RUN_LABEL))


def list_resources(namespace=NAMESPACE):
    result = subprocess.run(
        ["oc", "get", RESOURCES, "-n", namespace, "-o", "json", "--request-timeout=10s"],
        check=True, capture_output=True, text=True, timeout=30,
    )
    return json.loads(result.stdout).get("items", [])


def save_resource(directory, resource):
    with snapshot_lock(directory):
        if run_owner(resource) not in saved_stops(directory):
            _save_resource(directory, resource)


def _save_resource(directory, resource, force=False):
    """Save the complete CR atomically; never save providers or agents."""
    kind = resource.get("kind")
    if kind != "AgenticRun" and kind not in RESULT_KINDS:
        return
    metadata = resource["metadata"]
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", metadata["name"])
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{kind.lower()}-{name}.yaml"
    if path.exists():
        previous = yaml.safe_load(path.read_text())
        if previous.get("metadata", {}).get("uid") != metadata.get("uid"):
            path = directory / f"{kind.lower()}-{name}-{metadata['uid']}.yaml"
    if path.exists():
        previous = yaml.safe_load(path.read_text())
        if not force and int(previous["metadata"].get("resourceVersion", 0)) > int(metadata.get("resourceVersion", 0)):
            return
    content = yaml.safe_dump(resource, sort_keys=False, allow_unicode=True)
    if not path.exists() or path.read_text() != content:
        write_atomic(path, content)


def freeze_run(directory, name, namespace=NAMESPACE):
    """Take the final snapshot before framework or scenario cleanup."""
    directory = Path(directory)
    stopped_at = datetime.now(timezone.utc).isoformat()
    with snapshot_lock(directory):
        # Block watcher writes while collecting the final snapshot, including
        # results created between the API read and the stop record.
        resources = list_resources(namespace)
        run = next((cr for cr in resources if cr.get("kind") == "AgenticRun"
                    and cr["metadata"]["name"] == name), None)
        if run is None:
            raise ValueError(f"AgenticRun {name} was not found at eval stop")
        uid = run_owner(run)
        stops = saved_stops(directory)
        if uid not in stops:
            for resource in resources:
                if run_owner(resource) == uid:
                    _save_resource(directory, resource, force=True)
            stops[uid] = {"name": name, "stopped_at": stopped_at}
            write_atomic(directory / STOPS_FILE, json.dumps(stops, indent=2) + "\n")
    return uid


def record_eval_outcome(directory, uid, error):
    """Keep the framework outcome even if the cluster run completes later."""
    directory = Path(directory)
    with snapshot_lock(directory):
        stops = saved_stops(directory)
        stops[uid]["error"] = error
        stops[uid]["timed_out"] = bool(error and "Timeout after" in error)
        write_atomic(directory / STOPS_FILE, json.dumps(stops, indent=2) + "\n")


class CRCapture:
    """Watch new run CRs and their results for the duration of a session."""

    def __init__(self, directory, report):
        self.directory = Path(directory)
        self.report = report
        self.initial_runs = set()
        self.stop_event = threading.Event()
        self.threads = []
        self.processes = set()
        self.lock = threading.Lock()

    def start(self):
        try:
            initial = []
            versions = {}
            for resource in RESOURCES.split(","):
                result = subprocess.run(
                    ["oc", "get", resource, "-n", NAMESPACE, "-o", "json", "--request-timeout=5s"],
                    check=True, capture_output=True, text=True, timeout=7,
                )
                data = json.loads(result.stdout)
                initial.extend(data.get("items", []))
                versions[resource] = data["metadata"]["resourceVersion"]
            self.initial_runs = {run_owner(cr) for cr in initial if run_owner(cr)}
            self.directory.mkdir(parents=True, exist_ok=True)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            self.report(f"Cannot start CR capture: {getattr(error, 'stderr', None) or error}")
            return
        for resource, version in versions.items():
            thread = threading.Thread(target=self.watch, args=(resource, version))
            self.threads.append(thread)
            thread.start()

    def handle(self, resource):
        uid = run_owner(resource)
        if uid and uid not in self.initial_runs:
            with self.lock:
                save_resource(self.directory, resource)

    def refresh(self):
        for resource in list_resources():
            self.handle(resource)

    def watch(self, resource, version):
        """Keep deletion events too, so framework cleanup cannot lose results."""
        while not self.stop_event.is_set():
            query = urlencode({"watch": "true", "resourceVersion": version, "timeoutSeconds": "300"})
            url = f"/apis/agentic.openshift.io/v1alpha1/namespaces/{NAMESPACE}/{resource}?{query}"
            process = None
            try:
                with self.lock:
                    if self.stop_event.is_set():
                        return
                    process = subprocess.Popen(
                        ["oc", "get", f"--raw={url}"], stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True,
                    )
                    self.processes.add(process)
                for line in process.stdout:
                    event = json.loads(line)
                    if event["type"] in {"ADDED", "MODIFIED", "DELETED"}:
                        self.handle(event["object"])
                        version = event["object"]["metadata"]["resourceVersion"]
                    elif event["type"] == "ERROR":
                        # Relist if the API no longer has this resource version.
                        version = ""
                        break
                if not self.stop_event.is_set():
                    process.wait(timeout=3)
                    if process.returncode:
                        self.report(f"CR watch ended for {resource} (exit {process.returncode}); reconnecting.")
                    self.capture()
                    if not version:
                        data = subprocess.run(
                            ["oc", "get", resource, "-n", NAMESPACE, "-o", "json", "--request-timeout=5s"],
                            check=True, capture_output=True, text=True, timeout=7,
                        )
                        listing = json.loads(data.stdout)
                        for cr in listing.get("items", []):
                            self.handle(cr)
                        version = listing["metadata"]["resourceVersion"]
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                self.report(f"Cannot watch {resource}: {getattr(error, 'stderr', None) or error}")
            finally:
                if process is not None:
                    self.terminate(process)
                    process.stdout.close()
                    with self.lock:
                        self.processes.discard(process)
            self.stop_event.wait(2)

    @staticmethod
    def terminate(process):
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()

    def capture(self):
        try:
            self.refresh()
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            self.report(f"Cannot save CRs: {getattr(error, 'stderr', None) or error}")

    def stop(self):
        self.stop_event.set()
        with self.lock:
            processes = list(self.processes)
        for process in processes:
            self.terminate(process)
        for thread in self.threads:
            thread.join()
        if self.threads:
            self.capture()


class SavedCRs:
    """Match saved CRs to an eval entry using references, then request and agent."""

    def __init__(self, session):
        self.session = Path(session)
        self.stops = saved_stops(self.session / "crs")
        resources = {}
        directory = self.session / "crs"
        # Keep old sessions readable. Prefer YAML if both formats are present.
        paths = sorted(directory.glob("*.json")) + sorted(directory.glob("*.yaml"))
        for path in paths:
            try:
                resource = yaml.safe_load(path.read_text())
            except (OSError, ValueError, yaml.YAMLError):
                continue
            if not isinstance(resource, dict):
                continue
            if resource.get("kind") == "AgenticRun" or resource.get("kind") in RESULT_KINDS:
                metadata = resource.get("metadata", {})
                key = (resource["kind"], metadata.get("uid") or str(path))
                resources[key] = (path, resource)
        self.resources = list(resources.values())

    def match(self, entry, agent, run_index, metrics):
        references = {ref.get("name")
                      for step in (entry.get("agentic_run_status", {}).get("steps") or {}).values()
                      for ref in step.get("results", []) or []}
        names = set()
        for metric in metrics or []:
            if metric.get("conversation_group_id") != entry["conversation_group_id"]:
                continue
            if metric.get("turn_id") and entry.get("turn_id") and metric["turn_id"] != entry["turn_id"]:
                continue
            names.update(re.findall(r"for ['\"]([^'\"]+)['\"]", metric.get("reason", "")))
        runs = [(path, cr) for path, cr in self.resources if cr["kind"] == "AgenticRun"]
        direct = [(path, cr) for path, cr in runs
                  if cr["metadata"]["name"] in names
                  or any(ref.get("name") in references
                         for step in ((cr.get("status") or {}).get("steps") or {}).values()
                         for ref in step.get("results", []) or [])]
        if len(direct) == 1:
            return direct[0]
        # Only use chronological repeat matching when request and agent agree.
        candidates = [(path, cr) for path, cr in runs
                      if cr.get("spec", {}).get("analysis", {}).get("agent") == agent
                      and cr.get("spec", {}).get("request", "").strip() == entry.get("query", "").strip()
                      and entry.get("query", "").strip()]
        candidates.sort(key=lambda item: item[1]["metadata"].get("creationTimestamp", ""))
        return candidates[run_index - 1] if len(candidates) >= run_index else None

    def enrich(self, entries, agent, run_index, metrics):
        for entry in entries:
            timeout_metrics = [metric for metric in metrics or []
                               if metric.get("conversation_group_id") == entry["conversation_group_id"]
                               and (not metric.get("turn_id") or not entry.get("turn_id")
                                    or metric["turn_id"] == entry["turn_id"])
                               and "Timeout after" in metric.get("reason", "")]
            entry["eval_timed_out"] = bool(timeout_metrics)
            entry["eval_stopped_at"] = next(
                (metric.get("eval_stopped_at") for metric in timeout_metrics), None,
            )
            match = self.match(entry, agent, run_index, metrics)
            if match is None:
                continue
            path, run = match
            entry["agentic_run_status"] = run.get("status") or {}
            entry["agentic_run_cr"] = run
            stop = self.stops.get(run_owner(run), {})
            entry["crs_frozen"] = bool(stop)
            entry["eval_timed_out"] = bool(stop.get("timed_out") or timeout_metrics)
            entry["eval_stopped_at"] = stop.get("stopped_at") or entry["eval_stopped_at"]
            entry["cr_links"] = [("AgenticRun", str(path.relative_to(self.session)))]
            results = {}
            resources = sorted(self.resources, key=lambda item: item[1]["metadata"].get("creationTimestamp", ""))
            for result_path, cr in resources:
                phase = RESULT_KINDS.get(cr["kind"])
                if phase and run_owner(cr) == run["metadata"].get("uid"):
                    results.setdefault(phase, []).append(cr.get("status") or {})
                    entry["cr_links"].append((cr["kind"], str(result_path.relative_to(self.session))))
            entry["agentic_run_results"] = results
            usage = (run.get("status") or {}).get("tokenUsage") or {}
            entry["agent_input_tokens"] = usage.get("inputTokens")
            entry["agent_output_tokens"] = usage.get("outputTokens")
            started = run["metadata"].get("creationTimestamp")
            finished = (run.get("status") or {}).get("terminalTime")
            stopped = entry.get("eval_stopped_at")
            if stopped and (not finished or datetime.fromisoformat(finished.replace("Z", "+00:00"))
                            > datetime.fromisoformat(stopped.replace("Z", "+00:00"))):
                finished = stopped
                usage = {}
                for phase_results in results.values():
                    for result in phase_results:
                        if any(c.get("type") == "Completed" and c.get("lastTransitionTime")
                               and datetime.fromisoformat(c["lastTransitionTime"].replace("Z", "+00:00"))
                               <= datetime.fromisoformat(stopped.replace("Z", "+00:00"))
                               for c in result.get("conditions", [])):
                            for key, value in result.get("tokenUsage", {}).items():
                                usage[key] = usage.get(key, 0) + value
                entry["agent_input_tokens"] = usage.get("inputTokens")
                entry["agent_output_tokens"] = usage.get("outputTokens")
            if started and finished:
                entry["analysis_duration"] = (
                    datetime.fromisoformat(finished.replace("Z", "+00:00"))
                    - datetime.fromisoformat(started.replace("Z", "+00:00"))
                ).total_seconds()


def recover(session, names):
    """Recover existing CRs for the run names recorded in a session's logs."""
    if not names:
        names = {re.sub(r"-(analysis|execution|verification)(-\d+)?$", "", path.stem)
                 for path in (session / "logs").glob("*.log")}
    resources = list_resources()
    uids = {run_owner(cr) for cr in resources
            if cr.get("kind") == "AgenticRun" and cr["metadata"]["name"] in names}
    count = 0
    for resource in resources:
        if run_owner(resource) in uids:
            save_resource(session / "crs", resource)
            count += 1
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Recover AgenticRun and result CRs for a saved session.")
    parser.add_argument("session", type=Path)
    parser.add_argument("--runs", nargs="+", default=[])
    args = parser.parse_args()
    try:
        print(f"Saved {recover(args.session, set(args.runs))} CRs in {args.session / 'crs'}")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Cannot recover CRs: {getattr(error, 'stderr', None) or error}", file=sys.stderr)
        sys.exit(1)
