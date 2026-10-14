"""Run lightspeed-eval with CR snapshots at each AgenticRun eval stop."""

from pathlib import Path
import runpy
import sys
import threading

from agentic_crs import freeze_run, record_eval_outcome


def install_snapshot_hook(driver_type, directory):
    """Capture before cleanup on success, timeout, or another eval error."""
    cleanup = driver_type._cleanup
    execute = driver_type.execute_turn
    context = threading.local()

    def snapshot_cleanup(driver, name):
        try:
            uid = freeze_run(directory, name, driver._config.namespace)
            context.uid = uid
        except Exception as error:  # Capture must not replace the eval outcome.
            print(f"WARNING: Cannot save CRs at eval stop for {name}: {error}", file=sys.stderr, flush=True)
        return cleanup(driver, name)

    def snapshot_execute(driver, *args, **kwargs):
        context.uid = None
        result = execute(driver, *args, **kwargs)
        if context.uid is not None:
            try:
                record_eval_outcome(directory, context.uid, result[0])
            except Exception as error:
                print(f"WARNING: Cannot save eval outcome: {error}", file=sys.stderr, flush=True)
        return result

    driver_type._cleanup = snapshot_cleanup
    driver_type.execute_turn = snapshot_execute


def main():
    directory, command, *arguments = sys.argv[1:]
    from lightspeed_evaluation.pipeline.evaluation.driver import OpenshiftAgenticRunDriver

    install_snapshot_hook(OpenshiftAgenticRunDriver, Path(directory))
    sys.argv = [command, *arguments]
    runpy.run_path(command, run_name="__main__")


if __name__ == "__main__":
    main()
