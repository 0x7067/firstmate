# Herdr family-run step timeout evidence

The required Behavior tests (Herdr) lane now fails a hung family-run **step**
in 20 minutes while keeping the 75-minute job cap as a last-resort backstop.

## Contract consumed from the workflow (not a source grep)

Parsed `.github/workflows/ci.yml` with Ruby's YAML loader (same shape GitHub
Actions consumes) and validated the file against the published GitHub workflow
schema (`https://json.schemastore.org/github-workflow.json` via Ajv).

| Surface | Bound | Result |
|---|---:|---|
| `jobs.tests-herdr.timeout-minutes` | 75 | unchanged last-resort job backstop |
| step `Run real-Herdr family (serial, required)` `timeout-minutes` | 20 | new hang tripwire (~3x healthy wall) |
| portable parallel 1/2 job timeout | 10 | unchanged |
| portable serial job timeout | 15 | unchanged |
| cleanup `if` | `always()` | still after the family-run step |
| upload `if` | `always()` | still after cleanup |

Schema validation: **valid**. The family-run `timeout-minutes: 20` is a
positive integer, below the 75-minute job cap, and accepted by
`jobs.<job_id>.steps[*].timeout-minutes`.

GitHub's published workflow syntax:

- step `timeout-minutes` is "the maximum number of minutes to run the step
  before killing the process"
- job `timeout-minutes` is "the maximum number of minutes to let a job run
  before GitHub automatically cancels it"
- `if: always()` still runs later steps so cleanup and timing artifacts upload
  after a failed/cancelled predecessor

## Historical hang this change is meant to cut short

[CI run 31524483885](https://github.com/kunchenguid/firstmate/actions/runs/31524483885)
`Behavior tests (Herdr)`
[job 93952738551](https://github.com/kunchenguid/firstmate/actions/runs/31524483885/job/93952738551)

| Event | Timestamp (UTC) | Wall |
|---|---|---:|
| Job start | 2026-08-11T23:07:03Z | |
| Family-run step start | 2026-08-11T23:07:08Z | |
| Family-run step cancelled | 2026-08-12T00:22:16Z | **75.13 min** |
| Job cancelled | 2026-08-12T00:22:19Z | **75.27 min** |

The family-run step occupied the runner until the 75-minute job cap. Cleanup
and artifact upload only ran after that cancel (`always()`), so evidence
arrived ~55 minutes later than a 20-minute step timeout would have allowed.

## Healthy Herdr wall times (20 min is ~3x)

Recent successful `Behavior tests (Herdr)` family-run steps:

| Run | Family-run wall | Job wall |
|---|---:|---:|
| [31776529986](https://github.com/kunchenguid/firstmate/actions/runs/31776529986/job/94693008743) | 6.63 min | 6.77 min |
| [31775514421](https://github.com/kunchenguid/firstmate/actions/runs/31775514421/job/94690034248) | 6.68 min | 6.83 min |
| [31767745550](https://github.com/kunchenguid/firstmate/actions/runs/31767745550/job/94666990010) | 6.38 min | 6.55 min |
| [31749699206](https://github.com/kunchenguid/firstmate/actions/runs/31749699206/job/94612418785) | 6.15 min | 6.27 min |
| [31740468768](https://github.com/kunchenguid/firstmate/actions/runs/31740468768/job/94582333989) | 6.28 min | 6.43 min |

Healthy family-run wall is ~6.1–6.7 minutes. The 20-minute step bound sits
comfortably above that (~3x) and far below the 75-minute job backstop.

## Scope checks

- Only `.github/workflows/ci.yml`, `docs/fm-test-portable-shards.md`, and
  `tests/fm-test-run.test.sh` changed.
- Portable shard job timeouts stayed 10 / 10 / 15.
- No fork-PR / `action_required` approval path was touched.
- Herdr lifecycle, lab sessions, and family-run command body were not changed;
  the family-run step still invokes `bin/fm-test-run.sh --family real-herdr-gated`.
