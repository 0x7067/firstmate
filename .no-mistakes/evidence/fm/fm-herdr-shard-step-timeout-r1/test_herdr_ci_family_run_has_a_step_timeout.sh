#!/usr/bin/env bash
# Isolated copy of tests/fm-test-run.test.sh::test_herdr_ci_family_run_has_a_step_timeout
# so this phase can run the one relevant contract without the rest of the suite.
set -u
ROOT="${1:?repo root whose .github/workflows/ci.yml will be parsed}"
LIB_ROOT="${2:-$ROOT}"
# shellcheck source=/dev/null
. "$LIB_ROOT/tests/lib.sh"
# The sourced lib.sh overwrites ROOT from its own location. Restore the
# workflow tree under test (needed when we point at a baseline checkout).
ROOT="$1"

test_herdr_ci_family_run_has_a_step_timeout() {
  # The required Herdr lane's hang tripwire is the family-run *step* bound, not
  # the 75-minute job cap. Parse the workflow as YAML so nested `with.name`
  # artifact keys cannot masquerade as the step contract.
  command -v ruby >/dev/null 2>&1 \
    || fail "ruby is required to parse .github/workflows/ci.yml as YAML"
  local json job_timeout step_timeout
  json=$(ruby -ryaml -rjson -e '
doc = YAML.load_file(ARGV[0])
job = doc.fetch("jobs").fetch("tests-herdr")
step = job.fetch("steps").find { |s|
  s.is_a?(Hash) && s["name"] == "Run real-Herdr family (serial, required)"
}
raise "missing family-run step" if step.nil?
raise "family-run step has no timeout-minutes" unless step.key?("timeout-minutes")
puts JSON.generate(
  "job_timeout" => job.fetch("timeout-minutes"),
  "step_timeout" => step.fetch("timeout-minutes")
)
' "$ROOT/.github/workflows/ci.yml") \
    || fail "could not parse tests-herdr timeouts from ci.yml"
  job_timeout=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["job_timeout"])' <<<"$json") \
    || fail "could not read job timeout from parsed workflow"
  step_timeout=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["step_timeout"])' <<<"$json") \
    || fail "could not read step timeout from parsed workflow"
  [ "$job_timeout" = 75 ] \
    || fail "tests-herdr job backstop must stay 75 minutes, got $job_timeout"
  [ "$step_timeout" = 20 ] \
    || fail "family-run step timeout must be 20 minutes, got $step_timeout"
  [ "$step_timeout" -lt "$job_timeout" ] \
    || fail "family-run step timeout must be below the job backstop"
  pass "Herdr CI family-run step times out at 20 min under a 75 min job backstop"
}

test_herdr_ci_family_run_has_a_step_timeout
