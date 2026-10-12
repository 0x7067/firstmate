#!/usr/bin/env bash
set -eu
ROOT=$PWD
E=/home/denguinho/.no-mistakes/evidence/01M4RAVP51BZSKS54TT4H7KV5N
L=$(mktemp -d "$PWD/.gate-diagnostics.XXXXXX")
trap 'rm -rf "$L"' EXIT
bin/fm-lab-home.sh create "$L/home" >/dev/null
export FM_HOME="$L/home" STATE="$L/home/state" FM_ROOT="$ROOT" FM_BACKEND=tmux FM_SPAWN_NO_GUARD=1
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
for role in task-spawn forced-teardown unknown; do
 (
 . "$ROOT/bin/fm-wake-lib.sh"
 fm_lock_try_acquire "$STATE/.task-set.lock"
 [ "$role" = unknown ] || fm_lock_set_role "$STATE/.task-set.lock" "$role"
 trap 'fm_lock_release "$STATE/.task-set.lock"' EXIT
 rc=0; "$ROOT/bin/fm-spawn.sh" blocked --secondmate > "$L/out" 2>&1 || rc=$?
 printf 'holder=%s rc=%s\n' "$role" "$rc"
 cat "$L/out"
 [ "$rc" = 1 ] && [ ! -e "$STATE/blocked.meta" ] && [ -d "$STATE/.task-set.lock" ]
 case "$role" in
 task-spawn) grep -F 'locked by another spawn;' "$L/out" ;;
 forced-teardown) grep -F 'locked by a forced teardown;' "$L/out" ;;
 unknown) grep -F 'locked by another operation;' "$L/out" ;;
 esac
 printf 'metadata absent; holder lock preserved\n'
 )
done
