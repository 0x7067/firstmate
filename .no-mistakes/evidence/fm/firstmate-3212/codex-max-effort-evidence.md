# Codex max reasoning-effort — live validation evidence
branch: fm/firstmate-3212  base: ffd2c899  target: f50d010f

## Scenario 1: spawn codex with --effort max → real launch command
Drove bin/fm-spawn.sh end-to-end (fake tmux captures literal send-keys payload):

  spawned codex-max-ev1 harness=codex kind=ship mode=no-mistakes yolo=off
  meta: harness=codex model=gpt-5 effort=max
  LAUNCH: env -u CURSOR_AGENT -u CURSOR_INVOKED_AS -u GEMINI_CLI codex \
    --model 'gpt-5' -c 'model_reasoning_effort="max"' \
    --dangerously-bypass-approvals-and-sandbox -c "notify=[...]" "$(...)"

=> max is PASSED THROUGH to model_reasoning_effort, not omitted, not clamped.

## Scenario 2: installed codex catalog advertises max (intent's "pass it" branch)
  $ codex --version
  codex-cli 0.153.4
  $ codex debug models | grep -oE '"effort":"[a-z]+"' | sort -u
  "effort":"high" "effort":"low" "effort":"max" "effort":"medium" "effort":"ultra" "effort":"xhigh"

=> installed codex accepts max, so passing it (not clamping to xhigh) is correct.
Binary enum: "minimallowmediumhighxhighmaxultrapersistent".

## Scenario 3: crew-dispatch validation accepts codex effort=max
  tests/fm-bootstrap.test.sh → 28 ok, exit 0
  rows exercised: "codex max effort is accepted" (single + array profile) → no error;
  grok max/xhigh still flagged invalid (boundary preserved).

## Scenario 4: effort still bounded — ultra cannot reach codex emit
  bin/fm-spawn.sh:516  case "$EFFORT" in ''|low|medium|high|xhigh|max) ;; *) error; exit 1
  => 'ultra' rejected by shared vocabulary before harness mapping; codex emit set
     is low|medium|high|xhigh|max (no ultra).

## Test suites run
  tests/fm-spawn-dispatch-profile.test.sh → all passed (incl. test_codex_threads_max_effort)
  tests/fm-bootstrap.test.sh → 28 ok, exit 0
