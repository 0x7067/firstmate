# Herdr behavior shard: step-level hang tripwire

End-user of this change: a CI operator watching a wedged `Behavior tests (Herdr)` job.

## What the runner will do

Parsed `.github/workflows/ci.yml` as YAML (Psych / the same document GitHub Actions consumes). Not a text grep.

| | Base `6789876` | Target `221aebd` |
|---|---|---|
| Job `tests-herdr` `timeout-minutes` | 75 | 75 (kept as backstop) |
| Family-run step `timeout-minutes` | **missing** | **20** |
| Cleanup `if:` | `always()` | `always()` |
| Upload timing/diagnostics `if:` | `always()` | `always()` |

GitHub Actions semantics (docs.github.com workflow syntax):

- **Step** `timeout-minutes`: "The maximum number of minutes to run the step before killing the process."
- **Job** `timeout-minutes`: "The maximum number of minutes to let a job run before GitHub automatically cancels it."

A step kill leaves the job running, so the two `if: always()` steps after the family-run still execute. A job-cap cancel is the whole job stopping — that is the 75-minute hang the audit called out (run 31524483885).

20 minutes is above the ~7-minute healthy wall and far below the 75-minute backstop.

## Contract test (official suite function)

`tests/fm-test-run.test.sh::test_herdr_ci_family_run_has_a_step_timeout`

- Against **base** workflow: `not ok - could not parse tests-herdr timeouts from ci.yml` (`family-run step has no timeout-minutes`). Exit 1.
- Against **target** workflow: `ok - Herdr CI family-run step times out at 20 min under a 75 min job backstop`. Exit 0.

The reported failure exists before the fix and is gone after it.

## Hung-suite experience (scaled clock)

1 CI minute = 80 ms wall so a 75-minute occupation is observable without burning a runner.

```
BASE (job cap only)
  t=    0 min  family-run starts and wedges
  t=   75 min  job timeout-minutes=75 cancels the whole job (only stop)
  t=   75 min  cleanup/upload not a reliable evidence path
  => runner occupied 75 CI minutes; evidence_uploaded=false

TARGET (this change)
  t=    0 min  family-run starts and wedges
  t=   20 min  step timeout-minutes=20 fires; hung family-run is killed
  t= 20.5 min  Cleanup job-owned Herdr lab sessions ran (if: always())
  t= 21.0 min  Upload Herdr timing and diagnostics ran (if: always())
  => runner occupied 20 CI minutes; evidence_uploaded=true
```

A hang now fails ~55 runner-minutes sooner, with cleanup and the timing/diagnostics artifact still uploaded. The 75-minute job cap remains the last-resort backstop.

## Scope (forbidden work)

Changed files vs base: `.github/workflows/ci.yml`, `docs/fm-test-portable-shards.md`, `tests/fm-test-run.test.sh`.

- `tests/fm-procevent.test.sh` not touched.
- Diff does not mention `action_required` (the 479 fork-PR approvals stay out of scope).
