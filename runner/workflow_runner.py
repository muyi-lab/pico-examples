#!/usr/bin/env python3
"""
workflow_runner.py — YAML-driven workflow executor for pico-examples.

Usage:
    python3 runner/workflow_runner.py [workflow.yaml] [options]

Options:
    --param KEY=VALUE    Override a workflow param (repeatable)
    --dry-run            Print commands without executing
    --resume             Skip steps already completed in the state file
    --list-targets       Parse CMakeLists.txt and print available targets
    --project-root DIR   Root dir for --list-targets (default: .)
    --state-file PATH    State file path (default: workflow_state.json)

Requires: PyYAML  (pip install pyyaml)
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

# ANSI colours (disabled on non-tty)
_USE_COLOR = sys.stdout.isatty()
_C = {
    "cyan":   "\033[36m",
    "green":  "\033[32m",
    "yellow": "\033[33m",
    "red":    "\033[31m",
    "bold":   "\033[1m",
    "reset":  "\033[0m",
} if _USE_COLOR else defaultdict(str)

DEFAULT_STATE_FILE = "workflow_state.json"


# ---------------------------------------------------------------------------
# Template resolution  {{ params.key }} / {{ env.KEY }}
# ---------------------------------------------------------------------------

def resolve_template(text: str, context: Dict[str, Any]) -> str:
    """Substitute {{ a.b.c }} expressions from nested context dict."""
    def replacer(m: re.Match) -> str:
        parts = m.group(1).strip().split(".")
        val: Any = context
        for part in parts:
            if not isinstance(val, dict) or part not in val:
                return m.group(0)  # leave unresolved placeholder intact
            val = val[part]
        return str(val)

    return re.sub(r"\{\{\s*([\w.]+)\s*\}\}", replacer, text)


def resolve_all(obj: Any, context: Dict[str, Any]) -> Any:
    """Recursively resolve templates in strings, lists, and dicts."""
    if isinstance(obj, str):
        return resolve_template(obj, context)
    if isinstance(obj, list):
        return [resolve_all(item, context) for item in obj]
    if isinstance(obj, dict):
        return {k: resolve_all(v, context) for k, v in obj.items()}
    return obj


# ---------------------------------------------------------------------------
# Topological sort (Kahn's algorithm)
# ---------------------------------------------------------------------------

def topo_sort(steps: List[Dict]) -> List[Dict]:
    """Return steps in dependency order; raise ValueError on cycles or unknown deps."""
    id_to_step = {s["id"]: s for s in steps}
    dependents: Dict[str, List[str]] = defaultdict(list)
    in_degree: Dict[str, int] = {s["id"]: 0 for s in steps}

    for step in steps:
        for dep in step.get("depends_on", []):
            if dep not in id_to_step:
                raise ValueError(
                    f"Step '{step['id']}' depends on unknown step '{dep}'"
                )
            dependents[dep].append(step["id"])
            in_degree[step["id"]] += 1

    queue: deque = deque(sid for sid, deg in in_degree.items() if deg == 0)
    result: List[Dict] = []

    while queue:
        sid = queue.popleft()
        result.append(id_to_step[sid])
        for child in dependents[sid]:
            in_degree[child] -= 1
            if in_degree[child] == 0:
                queue.append(child)

    if len(result) != len(steps):
        raise ValueError("Circular dependency detected in workflow steps")

    return result


# ---------------------------------------------------------------------------
# Check runners
# ---------------------------------------------------------------------------

def run_check(
    check: Dict, context: Dict[str, Any], exec_env: Dict[str, str]
) -> Tuple[bool, str]:
    """Run one check rule. Returns (passed, message)."""
    ctype = check.get("type", "")

    if ctype == "exit_code":
        expected = int(check.get("value", 0))
        actual = context.get("_exit_code", -1)
        ok = actual == expected
        return ok, f"exit_code {actual} {'==' if ok else '!='} {expected}"

    if ctype == "file_exists":
        path = resolve_all(check["path"], context)
        exists = Path(path).exists()
        return exists, f"{'exists' if exists else 'MISSING'}: {path}"

    if ctype == "log_grep":
        filepath = resolve_all(check["file"], context)
        pattern = check["pattern"]
        try:
            content = Path(filepath).read_text(errors="replace")
            found = bool(re.search(pattern, content))
            return found, (
                f"pattern {'found' if found else 'NOT FOUND'}: "
                f"{pattern!r} in {filepath}"
            )
        except FileNotFoundError:
            return False, f"log file missing: {filepath}"

    if ctype == "command_output":
        cmd = resolve_all(check["command"], context)
        expected_substr = check.get("contains", "")
        try:
            r = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, env=exec_env
            )
            ok = expected_substr in r.stdout
            return ok, (
                f"output {'contains' if ok else 'MISSING'}: {expected_substr!r}"
            )
        except Exception as exc:
            return False, f"command error: {exc}"

    return False, f"unknown check type: {ctype!r}"


# ---------------------------------------------------------------------------
# State persistence
# ---------------------------------------------------------------------------

def load_state(state_file: str) -> Dict:
    try:
        return json.loads(Path(state_file).read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {"steps": {}}


def save_state(state: Dict, state_file: str) -> None:
    Path(state_file).write_text(json.dumps(state, indent=2))


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# Console output helpers
# ---------------------------------------------------------------------------

def _print(tag: str, msg: str = "", color: str = "") -> None:
    prefix = f"{_C[color]}[{tag}]{_C['reset']}"
    if msg:
        print(f"{prefix} {msg}")
    else:
        print(prefix)


def info(tag: str, msg: str = "")  -> None: _print(tag, msg, "cyan")
def ok(tag: str, msg: str = "")    -> None: _print(tag, msg, "green")
def warn(tag: str, msg: str = "")  -> None: _print(tag, msg, "yellow")
def err(tag: str, msg: str = "")   -> None: _print(tag, msg, "red")


# ---------------------------------------------------------------------------
# --list-targets
# ---------------------------------------------------------------------------

def list_targets(project_root: str) -> List[str]:
    """Scan CMakeLists.txt files for add_executable targets."""
    root = Path(project_root)
    targets: set = set()
    for cmake_file in sorted(root.rglob("CMakeLists.txt")):
        try:
            content = cmake_file.read_text(errors="replace")
            for m in re.finditer(
                r"add_executable\s*\(\s*(\w+)", content, re.IGNORECASE
            ):
                name = m.group(1)
                if not name.startswith("$"):
                    targets.add(name)
        except Exception:
            pass
    return sorted(targets)


# ---------------------------------------------------------------------------
# Core workflow executor
# ---------------------------------------------------------------------------

def run_workflow(
    workflow: Dict,
    params: Dict[str, str],
    *,
    dry_run: bool,
    resume: bool,
    state_file: str,
) -> int:
    wf_name = workflow.get("name", "workflow")
    info("WORKFLOW", f"{_C['bold']}{wf_name}{_C['reset']}")
    if workflow.get("description"):
        print(f"  {workflow['description'].strip()}")
    print()

    # Build template context (params first, then resolved env)
    context: Dict[str, Any] = {"params": params}

    raw_env: Dict[str, str] = {
        k: resolve_template(str(v), context)
        for k, v in workflow.get("env", {}).items()
    }
    # Expand $HOME / $VAR in env values resolved from params
    raw_env = {k: os.path.expandvars(v) for k, v in raw_env.items()}
    context["env"] = raw_env

    # Full subprocess environment = system env + workflow env
    exec_env: Dict[str, str] = {**os.environ, **raw_env}

    # Topological order
    try:
        ordered_steps = topo_sort(workflow.get("steps", []))
    except ValueError as exc:
        err("ERROR", str(exc))
        return 1

    # State for --resume
    state = load_state(state_file) if resume else {}
    state.setdefault("workflow", wf_name)
    state.setdefault("steps", {})
    completed = state["steps"]

    for step in ordered_steps:
        sid = step["id"]
        desc = resolve_template(step.get("description", sid), context)

        # --resume: skip completed steps
        if resume and completed.get(sid, {}).get("status") == "completed":
            warn("SKIP", f"{sid} — already completed")
            continue

        print(f"{_C['bold']}{'─' * 60}{_C['reset']}")
        info("STEP", f"{sid}")
        print(f"  {desc}")

        # Resolve the entire step with current context
        resolved = resolve_all(step, context)
        run_cmd: str = resolved.get("run", "")
        info("RUN", run_cmd)

        if dry_run:
            warn("DRY-RUN", "skipping execution")
            completed[sid] = {"status": "dry-run", "timestamp": now_iso()}
            save_state(state, state_file)
            print()
            continue

        # ---- Execute -------------------------------------------------------
        result = subprocess.run(run_cmd, shell=True, env=exec_env)
        exit_code = result.returncode

        # Context for check evaluation (adds _exit_code)
        step_ctx: Dict[str, Any] = {**context, "_exit_code": exit_code}

        # ---- Checks --------------------------------------------------------
        checks = resolved.get("check", [])
        all_checks_passed = True
        for chk in checks:
            passed, msg = run_check(chk, step_ctx, exec_env)
            if passed:
                ok("  ✓", msg)
            else:
                err("  ✗", msg)
                all_checks_passed = False

        # ---- Route on failure / success ------------------------------------
        on_failure = resolved.get("on_failure", {})
        on_success = resolved.get("on_success", {})
        step_failed = (exit_code != 0) or not all_checks_passed

        if step_failed:
            action = on_failure.get("action", "abort")
            hint = on_failure.get("message", "").strip()

            err("FAIL", sid)
            if hint:
                warn("HINT", hint)

            completed[sid] = {
                "status": "failed",
                "exit_code": exit_code,
                "timestamp": now_iso(),
            }
            save_state(state, state_file)

            if action == "abort":
                err("ABORT", "workflow stopped — fix the error above and re-run")
                err("TIP", f"Use --resume to skip already-completed steps")
                return 1

            if action == "retry":
                max_retries = int(on_failure.get("max_retries", 3))
                warn("RETRY", f"retrying up to {max_retries} more time(s)…")
                success = False
                for attempt in range(1, max_retries + 1):
                    warn("RETRY", f"attempt {attempt}/{max_retries}: {run_cmd}")
                    r2 = subprocess.run(run_cmd, shell=True, env=exec_env)
                    ec2 = r2.returncode
                    ctx2 = {**context, "_exit_code": ec2}
                    checks2 = [run_check(c, ctx2, exec_env)[0] for c in checks]
                    if ec2 == 0 and all(checks2):
                        completed[sid] = {
                            "status": "completed",
                            "exit_code": ec2,
                            "retries": attempt,
                            "timestamp": now_iso(),
                        }
                        save_state(state, state_file)
                        ok("OK", f"{sid} succeeded after {attempt} retry(ies)")
                        success = True
                        break
                if not success:
                    err("ABORT", f"step '{sid}' failed after {max_retries} retries")
                    return 1

            # action == "report": log and continue
            if action == "report":
                warn("REPORT", f"step '{sid}' failed but workflow continues")

        else:
            # Success path
            success_msg = on_success.get("message", "").strip()
            if success_msg:
                ok("OK", success_msg)
            else:
                ok("OK", sid)

            completed[sid] = {
                "status": "completed",
                "exit_code": exit_code,
                "timestamp": now_iso(),
            }
            save_state(state, state_file)

            next_step = on_success.get("next")
            if next_step:
                info("NEXT", next_step)

        print()

    print(f"{_C['bold']}{'─' * 60}{_C['reset']}")
    ok("DONE", f"workflow '{wf_name}' complete")
    print(f"  State saved → {state_file}")
    return 0


# ---------------------------------------------------------------------------
# Param resolution helpers
# ---------------------------------------------------------------------------

def resolve_params(workflow: Dict, cli_overrides: List[str]) -> Dict[str, str]:
    """Merge workflow param defaults with CLI --param KEY=VALUE overrides."""
    param_defs = workflow.get("params", {})
    params: Dict[str, str] = {}

    for key, defn in param_defs.items():
        if isinstance(defn, dict):
            default = defn.get("default", "")
        else:
            default = defn
        # Expand $HOME etc. in defaults
        params[key] = os.path.expandvars(str(default)) if isinstance(default, str) else str(default)

    for kv in cli_overrides:
        if "=" not in kv:
            sys.exit(f"--param must be KEY=VALUE, got: {kv!r}")
        k, v = kv.split("=", 1)
        if k not in params:
            known = ", ".join(param_defs.keys())
            sys.exit(f"Unknown param '{k}'. Known params: {known}")
        params[k] = v

    return params


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="YAML-driven workflow runner for pico-examples",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "workflow",
        nargs="?",
        default="workflows/build_example.yaml",
        help="Path to workflow YAML (default: workflows/build_example.yaml)",
    )
    parser.add_argument(
        "--param",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Override a workflow param (repeatable, e.g. --param target=hello_usb)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without executing",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Skip steps already marked 'completed' in the state file",
    )
    parser.add_argument(
        "--list-targets",
        action="store_true",
        help="Scan CMakeLists.txt files and list available build targets",
    )
    parser.add_argument(
        "--project-root",
        default=".",
        metavar="DIR",
        help="Project root for --list-targets (default: .)",
    )
    parser.add_argument(
        "--state-file",
        default=DEFAULT_STATE_FILE,
        metavar="PATH",
        help=f"Execution state file (default: {DEFAULT_STATE_FILE})",
    )

    args = parser.parse_args()

    # --list-targets is standalone
    if args.list_targets:
        targets = list_targets(args.project_root)
        if targets:
            print(f"Found {len(targets)} CMake target(s) in {args.project_root}:")
            for t in targets:
                print(f"  {t}")
        else:
            print(f"No add_executable targets found under {args.project_root}")
        return 0

    # Load workflow YAML
    wf_path = Path(args.workflow)
    if not wf_path.exists():
        sys.exit(f"Workflow file not found: {wf_path}")

    try:
        workflow = yaml.safe_load(wf_path.read_text())
    except yaml.YAMLError as exc:
        sys.exit(f"YAML parse error in {wf_path}: {exc}")

    if not isinstance(workflow, dict):
        sys.exit(f"Workflow file must be a YAML mapping: {wf_path}")

    # Resolve params
    try:
        params = resolve_params(workflow, args.param)
    except SystemExit:
        raise
    except Exception as exc:
        sys.exit(f"Param error: {exc}")

    # Print resolved params for visibility
    info("PARAMS", "")
    for k, v in params.items():
        print(f"  {k} = {v}")
    print()

    return run_workflow(
        workflow,
        params,
        dry_run=args.dry_run,
        resume=args.resume,
        state_file=args.state_file,
    )


if __name__ == "__main__":
    sys.exit(main())
