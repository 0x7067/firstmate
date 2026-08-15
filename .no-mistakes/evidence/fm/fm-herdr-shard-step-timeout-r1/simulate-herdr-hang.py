#!/usr/bin/env python3
"""Compressed simulation of a hung Herdr family-run under two timeout models.

Uses the real workflow YAML (parsed, not grepped) as the source of job/step
timeouts and always() cleanup/upload wiring. Time is scaled so one CI minute
is SCALE real seconds. A hung suite never finishes; the timeout model decides
when the runner is released and whether evidence steps still run.

This is the end-user experience of the change: a wedged shard must fail fast
with cleanup + artifact upload instead of occupying a runner to the job cap.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None


SCALE = 0.08  # 1 CI minute -> 80ms wall. 20 min ~ 1.6s; 75 min ~ 6s.


def load_model(path: Path) -> dict:
    if yaml is None:
        # Fall back to the ruby helper sitting next to this script.
        import subprocess

        helper = Path(__file__).with_name("parse-herdr-timeouts.rb")
        raw = subprocess.check_output(["ruby", str(helper), str(path)], text=True)
        return json.loads(raw)
    doc = yaml.safe_load(path.read_text())
    job = doc["jobs"]["tests-herdr"]
    steps = job["steps"]
    family = next(
        s
        for s in steps
        if isinstance(s, dict)
        and s.get("name") == "Run real-Herdr family (serial, required)"
    )
    cleanup = next(
        s
        for s in steps
        if isinstance(s, dict) and s.get("name") == "Cleanup job-owned Herdr lab sessions"
    )
    upload = next(
        s
        for s in steps
        if isinstance(s, dict) and s.get("name") == "Upload Herdr timing and diagnostics"
    )
    return {
        "job_timeout_minutes": job.get("timeout-minutes"),
        "family_run_step": {
            "name": family.get("name"),
            "timeout_minutes": family.get("timeout-minutes"),
            "has_timeout": "timeout-minutes" in family,
        },
        "cleanup_step": {
            "name": cleanup.get("name"),
            "if": cleanup.get("if"),
            "runs_after_step_failure_or_cancel": "always()" in str(cleanup.get("if")),
        },
        "upload_step": {
            "name": upload.get("name"),
            "if": upload.get("if"),
            "runs_after_step_failure_or_cancel": "always()" in str(upload.get("if")),
        },
    }


def simulate(label: str, model: dict, job_cancelled_skips_remaining: bool) -> dict:
    """Simulate a hung family-run.

    GitHub Actions semantics encoded here:
    - A *step* timeout kills only that step. The job is still running, so later
      steps with if: always() execute (cleanup + artifact upload).
    - A *job* timeout cancels the job. Remaining steps are not a reliable
      evidence path; the runner is held until the job cap.
    """
    job_cap = int(model["job_timeout_minutes"])
    step_to = model["family_run_step"].get("timeout_minutes")
    cleanup_ok = model["cleanup_step"]["runs_after_step_failure_or_cancel"]
    upload_ok = model["upload_step"]["runs_after_step_failure_or_cancel"]

    events: list[dict] = []
    t0 = time.perf_counter()

    def mark(ci_min: float, msg: str, **extra) -> None:
        events.append({"t_ci_min": round(ci_min, 2), "event": msg, **extra})

    mark(0, f"{label}: family-run starts and wedges (suite never returns)")

    if step_to is not None:
        tripwire = int(step_to)
        time.sleep(tripwire * SCALE)
        mark(
            tripwire,
            f"step timeout-minutes={tripwire} fires; hung family-run is killed",
            conclusion="failure",
        )
        runner_held = tripwire
        job_still_running = True
        if job_still_running and cleanup_ok:
            time.sleep(0.5 * SCALE)
            mark(tripwire + 0.5, "Cleanup job-owned Herdr lab sessions ran (if: always())")
        if job_still_running and upload_ok:
            time.sleep(0.5 * SCALE)
            mark(
                tripwire + 1.0,
                "Upload Herdr timing and diagnostics ran (if: always())",
            )
            evidence = True
        else:
            evidence = False
        fail_fast = runner_held < job_cap
    else:
        time.sleep(job_cap * SCALE)
        mark(
            job_cap,
            f"job timeout-minutes={job_cap} cancels the whole job (only stop)",
            conclusion="cancelled",
        )
        runner_held = job_cap
        # Job cancellation is the stop. always() steps are not a reliable
        # evidence path once the job itself has been cancelled at the cap.
        if job_cancelled_skips_remaining:
            mark(
                job_cap,
                "job cancelled at cap; cleanup/upload not a reliable evidence path",
            )
            evidence = False
        fail_fast = False

    wall = time.perf_counter() - t0
    return {
        "label": label,
        "job_timeout_minutes": job_cap,
        "step_timeout_minutes": step_to,
        "runner_held_ci_minutes": runner_held,
        "fail_fast": fail_fast,
        "evidence_uploaded": evidence,
        "wall_seconds": round(wall, 3),
        "events": events,
    }


def main() -> int:
    target_yml = Path(sys.argv[1])
    base_yml = Path(sys.argv[2])
    out_path = Path(sys.argv[3])

    target = load_model(target_yml)
    base = load_model(base_yml)

    base_run = simulate("BASE (job cap only)", base, job_cancelled_skips_remaining=True)
    target_run = simulate(
        "TARGET (step tripwire + job backstop)", target, job_cancelled_skips_remaining=True
    )

    saved = 75 - int(target_run["runner_held_ci_minutes"])
    report = {
        "scale": f"1 CI minute = {SCALE}s wall",
        "base": base_run,
        "target": target_run,
        "delta": {
            "runner_minutes_saved_on_hang": saved,
            "evidence_only_on_target": target_run["evidence_uploaded"]
            and not base_run["evidence_uploaded"],
            "target_step_above_healthy_7min": (
                target_run["step_timeout_minutes"] is not None
                and target_run["step_timeout_minutes"] > 7
            ),
            "target_step_far_below_75": (
                target_run["step_timeout_minutes"] is not None
                and target_run["step_timeout_minutes"] < 75 / 2
            ),
        },
    }
    out_path.write_text(json.dumps(report, indent=2) + "\n")

    lines = [
        "Herdr hang tripwire — compressed end-user simulation",
        f"Time scale: {report['scale']} (so a 75-min occupation is observable)",
        "",
        "BASE (before the change): tests-herdr has only timeout-minutes: 75 on the job.",
        "A wedged family-run holds the runner until that job cap. Cleanup/upload are",
        "not a reliable evidence path once the job itself is cancelled.",
        "",
    ]
    for ev in base_run["events"]:
        lines.append(f"  t={ev['t_ci_min']:>5} min  {ev['event']}")
    lines += [
        f"  => runner occupied {base_run['runner_held_ci_minutes']} CI minutes; "
        f"evidence_uploaded={base_run['evidence_uploaded']}",
        "",
        "TARGET (this change): family-run step timeout-minutes: 20; job stays 75.",
        "A wedged family-run is killed at 20 minutes. The job is still running, so",
        "if: always() cleanup and artifact upload still execute.",
        "",
    ]
    for ev in target_run["events"]:
        lines.append(f"  t={ev['t_ci_min']:>5} min  {ev['event']}")
    lines += [
        f"  => runner occupied {target_run['runner_held_ci_minutes']} CI minutes; "
        f"evidence_uploaded={target_run['evidence_uploaded']}",
        "",
        f"Saved ~{saved} runner-minutes on a hang. Job cap remains the last-resort backstop.",
    ]
    print("\n".join(lines))

    ok = (
        target_run["fail_fast"]
        and target_run["evidence_uploaded"]
        and not base_run["fail_fast"]
        and target_run["step_timeout_minutes"] == 20
        and target_run["job_timeout_minutes"] == 75
        and saved >= 50
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
