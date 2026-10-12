#!/usr/bin/env bash
set -eu
ROOT=$PWD
LAB=$ROOT/.live-pr-lab
export FM_HOME=$LAB/home TMUX_TMPDIR=$(cat "$LAB/socket-dir")
export TMUX=$(tmux -L fm-lab display-message -p -t primary '#{socket_path},#{pid},0')
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS HERDR_ENV HERDR_SESSION HERDR_PANE_ID
ID=$(cat "$LAB/id")
printf '%s\n' "$$" > "$FM_HOME/state/.lock"
printf '%s on\n' "$$" > "$FM_HOME/state/.trace-context-effective"
echo 'RECOVERY: relaunching the base-produced broken record with the target implementation'
FM_SPAWN_NO_GUARD=1 FM_CONTROL_POLL=0.2 FM_CONTROL_EXIT_WAIT=15 FM_CONTROL_LAUNCH_WAIT=15 bin/fm-control.sh "$ID" relaunch --note 'Disposable validation only: reply READY then wait; do not use tools or change files.'
. bin/fm-pr-lib.sh
fm_pr_poll_snapshot_capture "$FM_HOME/state" "$ID" "$ROOT/bin/fm-pr-poll.sh"
echo 'RECOVERY: original PR watch accepted without re-registration'
cat "$FM_HOME/state/$ID.meta"
sha256sum "$FM_HOME/state/$ID.check.sh" "$FM_HOME/state/$ID.pr-poll" > "$LAB/recovery.hash"
cmp "$LAB/before.hash" "$LAB/recovery.hash"
echo 'RECOVERY: original check and sidecar bytes unchanged'
