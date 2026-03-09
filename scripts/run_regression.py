#!/usr/bin/env python3
"""
run_regression.py — Run the full standalone smoke-test regression suite.

Iterates over every no-extra-hardware target for the plain Pico (RP2040),
calling the smoke_test workflow for each one, then prints a summary table.

Usage:
    python3 scripts/run_regression.py [--board pico] [--log-dir logs/regression]
                                      [--stop-on-fail] [--targets target1,target2]

Exit code: 0 if all pass, 1 if any fail.
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# ---------------------------------------------------------------------------
# Regression target definitions
# Format: (target_name, uart_expect_pattern)
# Empty pattern → UART check skipped (e.g. visual-only targets)
# ---------------------------------------------------------------------------
REGRESSION_TARGETS = [
    ("hello_serial",        "Hello, world"),
    ("hello_multicore",     "Hello, multicore"),
    ("hello_timer",         "Hello Timer"),
    ("hello_dma",           r"Hello, world! \(from DMA\)"),
    ("onboard_temperature", "Onboard temperature"),
    ("hello_watchdog",      "Hello, watchdog"),
    ("hello_rtc",           r"\d{4}-\d{2}-\d{2}"),   # date pattern e.g. 2020-06-05
    ("hello_uart",          "Hello, UART"),
    ("rand",                "Random 32bits"),
    ("unique_board_id",     "."),                      # any non-empty output
]

PASS = "PASS"
FAIL = "FAIL"
SKIP = "SKIP"


def run_target(target: str, pattern: str, board: str, log_dir: str,
               state_file: str) -> tuple[str, str]:
    """Run the smoke_test workflow for one target. Returns (status, message)."""
    cmd = [
        sys.executable,
        "runner/workflow_runner.py",
        "workflows/smoke_test.yaml",
        f"--param", f"target={target}",
        f"--param", f"board={board}",
        f"--param", f"uart_expect_pattern={pattern}",
        f"--param", f"log_dir={log_dir}",
        f"--state-file", state_file,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        return PASS, ""
    # Extract last non-empty line as short error message
    lines = [l.strip() for l in (result.stdout + result.stderr).splitlines() if l.strip()]
    msg = lines[-1] if lines else "unknown error"
    return FAIL, msg


def main() -> int:
    parser = argparse.ArgumentParser(description="Pico regression test suite")
    parser.add_argument("--board", default="pico", help="Board type (default: pico)")
    parser.add_argument("--log-dir", default="logs/regression",
                        help="Directory for per-target logs (default: logs/regression)")
    parser.add_argument("--stop-on-fail", action="store_true",
                        help="Abort after the first failure")
    parser.add_argument("--targets", default="",
                        help="Comma-separated subset of targets to run (default: all)")
    args = parser.parse_args()

    log_dir = Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)

    subset = {t.strip() for t in args.targets.split(",") if t.strip()}
    targets = [(t, p) for t, p in REGRESSION_TARGETS if not subset or t in subset]

    if not targets:
        print(f"No matching targets for: {args.targets}")
        return 1

    run_ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    results = []

    print(f"\n{'='*60}")
    print(f"  Pico Regression Suite — {len(targets)} target(s) — board={args.board}")
    print(f"{'='*60}\n")

    for i, (target, pattern) in enumerate(targets, 1):
        prefix = f"[{i}/{len(targets)}]"
        print(f"{prefix} {target} ...", end=" ", flush=True)

        target_log_dir = log_dir / target
        target_log_dir.mkdir(parents=True, exist_ok=True)
        target_log_dir = str(target_log_dir)
        state_file = str(log_dir / f"state_{target}_{run_ts}.json")

        status, msg = run_target(target, pattern, args.board, target_log_dir, state_file)

        if status == PASS:
            print("PASS")
        else:
            print(f"FAIL  — {msg}")

        results.append({
            "target":  target,
            "pattern": pattern,
            "status":  status,
            "message": msg,
        })

        if status == FAIL and args.stop_on_fail:
            print("\n[stop-on-fail] Aborting after first failure.")
            break

    # ---- Summary table -------------------------------------------------------
    passed = sum(1 for r in results if r["status"] == PASS)
    failed = sum(1 for r in results if r["status"] == FAIL)

    print(f"\n{'='*60}")
    print(f"  Results: {passed} passed, {failed} failed / {len(results)} run")
    print(f"{'='*60}")
    col_w = max(len(r["target"]) for r in results) + 2
    for r in results:
        mark = "OK" if r["status"] == PASS else "!!"
        note = f"  {r['message']}" if r["message"] else ""
        print(f"  [{mark}] {r['target']:<{col_w}}{note}")
    print()

    # ---- Save JSON report ----------------------------------------------------
    report_path = log_dir / f"regression_report_{run_ts}.json"
    symlink_path = log_dir / "regression_report.json"
    report = {
        "timestamp": run_ts,
        "board": args.board,
        "passed": passed,
        "failed": failed,
        "total": len(results),
        "results": results,
    }
    report_path.write_text(json.dumps(report, indent=2))
    # Update stable symlink
    if symlink_path.is_symlink() or symlink_path.exists():
        symlink_path.unlink()
    symlink_path.symlink_to(report_path.name)
    print(f"  Report: {symlink_path}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
