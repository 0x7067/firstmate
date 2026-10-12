#!/usr/bin/env bash
set -eu
ROOT=$PWD
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4RF1XCBWMY5KDPKASH524ZJ
LAB=$(mktemp -d "$PWD/.nm-locks.XXXXXX")
SOCKET_DIR=''
cleanup() {
  [ -z "$SOCKET_DIR" ] || TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab kill-server 2>/dev/null || true
  [ -z "$SOCKET_DIR" ] || bin/fm-lab-home.sh teardown "$LAB/home" || true
  rm -rf "$LAB"
}
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB/home" >/dev/null
export FM_HOME="$LAB/home" STATE="$LAB/home/state" FM_ROOT="$ROOT"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
. bin/fm-wake-lib.sh
exec > >(tee "$EVIDENCE/live-locks.log") 2>&1
for role in task-spawn forced-teardown unknown; do
  lock=$(fm_task_set_lock_path "$STATE")
  fm_lock_try_acquire "$lock"
  if [ "$role" != unknown ]; then fm_lock_set_role "$lock" "$role"; fi
  echo "SCENARIO: fresh spawn while lock holder role=$role"
  rc=0
  bin/fm-spawn.sh race --secondmate > "$LAB/refusal" 2>&1 || rc=$?
  cat "$LAB/refusal"
  [ "$rc" = 1 ] && [ ! -e "$STATE/race.meta" ] && [ -d "$lock" ]
  case "$role" in
    task-spawn) grep -F 'locked by another spawn' "$LAB/refusal" ;;
    forced-teardown) grep -F 'locked by a forced teardown' "$LAB/refusal" ;;
    unknown) grep -F 'locked by another operation;' "$LAB/refusal" ;;
  esac
  fm_lock_release "$lock"
  echo 'Verified: refusal preserved holder lock and published no task.'
done
SOCKET_DIR=$(bin/fm-lab-home.sh tmux-dir "$LAB/home")
env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab new-session -d -x 120 -y 40 -s primary -c "$ROOT" -e FM_HOME="$FM_HOME" codex
TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab new-window -d -t primary -n fm-race 'bash --noprofile --norc'
export TMUX
TMUX=$(TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab display-message -p -t primary '#{socket_path},#{pid},0')
fm_lock_try_acquire "$STATE/.secondmate-relaunch.lock"
cat > "$STATE/race.meta" <<EOF
kind=secondmate
backend=tmux
window=primary:fm-race
harness=codex
EOF
# Hold the lock in this process while a separate real recovery process waits.
echo 'SCENARIO: bounded recovery wait under a live per-home relaunch lock'
FM_ROOT="$ROOT" bash -c '
. "$FM_ROOT/bin/fm-secondmate-liveness-lib.sh"
fm_secondmate_liveness_probe "$STATE/race.meta" race poll
printf "Initial endpoint state=%s kill=%s\n" "$FM_SM_LIVE_STATE" "$FM_SM_LIVE_KILL"
[ "$FM_SM_LIVE_STATE" = dead ] && [ "$FM_SM_LIVE_KILL" = 1 ]
rc=0
fm_secondmate_liveness_relaunch "$STATE/race.meta" race 1 || rc=$?
printf "rc=%s status=%s reason=%s\n" "$rc" "$FM_SM_LIVE_STATUS" "$FM_SM_LIVE_REASON"
[ "$rc" = 1 ] && [ "$FM_SM_LIVE_STATUS" = skipped ]
[ ! -e "$STATE/.secondmate-relaunch-race" ]
' 
[ -d "$STATE/.secondmate-relaunch.lock" ]
TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab display-message -p -t primary:fm-race 'Preserved endpoint #{window_name}, foreground #{pane_current_command}, grid #{pane_width}x#{pane_height}'
fm_lock_release "$STATE/.secondmate-relaunch.lock"
echo 'Verified: no attempt ledger created, holder lock preserved, recovery skipped before spawn.'
