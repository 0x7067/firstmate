#!/usr/bin/env bash
set -eu
ROOT=$PWD
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4RJ0167AJ3KJSRCWCSBY66K
LAB=$(mktemp -d "$PWD/.live-lab.XXXXXX")
holder=''
cleanup() {
  [ -z "$holder" ] || kill "$holder" 2>/dev/null || true
  rm -rf "$LAB"
}
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB/parent" >/dev/null
mkdir -p "$LAB/mate" 
printf 'claude\n' > "$LAB/parent/config/secondmate-harness"
export FM_HOME="$LAB/parent" FM_BACKEND=tmux FM_SPAWN_NO_GUARD=1
unset FM_GATE_REFUSE_BYPASS FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
# Real spawn CLI is stopped by the live task-set lock before it creates an endpoint.
for role in task-spawn forced-teardown unknown; do
  (
    . "$ROOT/bin/fm-wake-lib.sh"
    lock=$(fm_task_set_lock_path "$STATE")
    fm_lock_try_acquire "$lock"
    [ "$role" = unknown ] || fm_lock_set_role "$lock" "$role"
    touch "$LAB/ready"
    trap 'fm_lock_release "$lock"' EXIT
    sleep 30
  ) &
  holder=$!
  for i in {1..100}; do [ ! -f "$LAB/ready" ] || break; sleep .05; done
  test -f "$LAB/ready"
  set +e
  bin/fm-spawn.sh mate "$LAB/mate" --secondmate > "$LAB/output" 2>&1
  rc=$?
  set -e
  printf '\nLOCK HOLDER=%s CLI EXIT=%s\n' "$role" "$rc"
  cat "$LAB/output"
  test "$rc" -ne 0
  case "$role" in
    task-spawn) grep -F 'task set is locked by another spawn' "$LAB/output" ;;
    forced-teardown) grep -F 'task set is locked by a forced teardown' "$LAB/output" ;;
    unknown) grep -F 'task set is locked by another operation;' "$LAB/output" ;;
  esac
  test ! -e "$LAB/parent/state/mate.meta"
  kill "$holder"; wait "$holder" || true; holder=''; rm "$LAB/ready"
done
# Attempt the supported real spawn without contention, within the allowed workspace.
set +e
bin/fm-spawn.sh mate "$LAB/mate" --secondmate > "$LAB/output" 2>&1
rc=$?
set -e
printf '\nWORKSPACE HOME ATTEMPT CLI EXIT=%s\n' "$rc"
cat "$LAB/output"
grep -F 'secondmate home cannot be inside the firstmate repo' "$LAB/output"
# Drive the production liveness library while a separate live process owns its home lock.
(
 . "$ROOT/bin/fm-wake-lib.sh"
 fm_lock_try_acquire "$STATE/.secondmate-relaunch.lock"
 touch "$LAB/ready"
 trap 'fm_lock_release "$STATE/.secondmate-relaunch.lock"' EXIT
 sleep 30
) &
holder=$!
for i in {1..100}; do [ ! -f "$LAB/ready" ] || break; sleep .05; done
test -f "$LAB/ready"
(
 . "$ROOT/bin/fm-secondmate-liveness-lib.sh"
 . "$ROOT/bin/fm-wake-lib.sh"
 FM_SM_LIVE_STATE=dead FM_SM_LIVE_KILL=1
 printf 'window=firstmate:fm-mate\nkind=secondmate\n' > "$STATE/mate.meta"
 cp "$STATE/mate.meta" "$LAB/before.meta"
 started=$SECONDS
 if fm_secondmate_liveness_relaunch "$STATE/mate.meta" mate 1; then exit 1; fi
 printf '\nBOUNDED WAIT: status=%s rc=%s elapsed=%ss reason=%s\n' "$FM_SM_LIVE_STATUS" "$FM_SM_LIVE_RC" "$((SECONDS-started))" "$FM_SM_LIVE_REASON"
 test "$FM_SM_LIVE_STATUS" = skipped
 test "$FM_SM_LIVE_RC" = 1
 test ! -e "$STATE/.secondmate-relaunch-mate"
 cmp "$LAB/before.meta" "$STATE/mate.meta"
 printf 'No relaunch attempt ledger or metadata change after lock timeout.\n'
)
kill "$holder"; wait "$holder" || true; holder=''
printf '\nLab removed by cleanup trap.\n'
