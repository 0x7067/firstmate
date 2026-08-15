#!/usr/bin/env bash
# Focused runner for test_herdr_ci_family_run_has_a_step_timeout only.
# Lives in the evidence directory so the worktree stays clean.
set -u
ROOT="${1:?repo root}"
cd "$ROOT" || exit 2
# shellcheck source=/dev/null
. "$ROOT/tests/lib.sh"

# Pull just the one test function from the suite file, then invoke it.
# The suite file also calls every test at the bottom; we must not source it.
func_src=$(awk '
  /^test_herdr_ci_family_run_has_a_step_timeout\(\)/ {capture=1}
  capture {print}
  capture && /^}/ {exit}
' "$ROOT/tests/fm-test-run.test.sh")
[ -n "$func_src" ] || { echo "not ok - could not extract test function" >&2; exit 1; }
eval "$func_src"
test_herdr_ci_family_run_has_a_step_timeout
