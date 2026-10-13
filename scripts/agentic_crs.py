"""Save AgenticRun and result CRs, and read them without cluster access."""

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import subprocess
import sys
import threading
from urllib.parse import urlencode

from report_progress import write_atomic


NAMESPACE = "openshift-lightspeed"
RUN_LABEL = "agentic.openshift.io/run"
RESULT_KINDS = {
    "AnalysisResult": "analysis", "ExecutionResult": "execution",
    "VerificationResult": "verification", "EscalationResult": "escalation",
}
RESOURCES = "agenticruns,analysisresults,executionresults,verificationresults,escalationresults"


def run_owner(resource):
    """Use the parent UID to avoid mixing runs with the same name."""
    if resource.get("kind") == "AgenticRun":
        return resource.get("metadata", {}).get("uid")
    metadata = resource.get("metadata", {})
    return next((owner.get("uid") for owner in metadata.get("ownerReferences", []) or []
                 if owner.get("kind") == "AgenticRun"
                 and owner.get("apiVersion", "").startswith("agentic.openshift.io/")),
                metadata.get("labels", {}).get(RUN_LABEL))


def list_resources():
    result = subprocess.run(
        ["oc", "get", RESOURCES, "-n", NAMESPACE, "-o", "json", "--request-timeout=10s"],
        check=True, capture_output=True, text=True, timeout=30,
    )
    return json.loads(result.stdout).get("items", [])


def save_resource(directory, resource):
    """Save the complete CR atomically; never save providers or agents."""
    kind = resource.get("kind")
    if kind != "AgenticRun" and kind not in RESULT_KINDS:
        return
    metadata = resource["metadata"]
    name = re.sub(r"[^A-Za-z0-9_.-]", "_", metadata["name"])
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{kind.lower()}-{name}.json"
    if path.exists():
        previous = json.loads(path.read_text())
        if previous.get("metadata", {}).get("uid") != metadata.get("uid"):
            path = directory / f"{kind.lower()}-{name}-{metadata['uid']}.json"
        elif int(previous["metadata"].get("resourceVersion", 0)) > int(metadata.get("resourceVersion", 0)):
            return
    content = json.dumps(resource, indent=2) + "\n"
    if not path.exists() or path.read_text() != content:
        write_atomic(path, content)


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
        self.resources = []
        for path in sorted((self.session / "crs").glob("*.json")):
            try:
                resource = json.loads(path.read_text())
            except (OSError, ValueError):
                continue
            if resource.get("kind") == "AgenticRun" or resource.get("kind") in RESULT_KINDS:
                self.resources.append((path, resource))

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
            match = self.match(entry, agent, run_index, metrics)
            if match is None:
                continue
            path, run = match
            entry["agentic_run_status"] = run.get("status") or {}
            entry["agentic_run_cr"] = run
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
