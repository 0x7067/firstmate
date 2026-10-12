#!/usr/bin/env bash
set -eu
ROOT=$PWD
LAB=$ROOT/.live-pr-lab
export FM_HOME=$LAB/home
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS HERDR_ENV HERDR_SESSION HERDR_PANE_ID
export TMUX_TMPDIR=$(cat "$LAB/socket-dir")
export TMUX=$(tmux -L fm-lab display-message -p -t primary '#{socket_path},#{pid},0')
ID=prlab-$$
tmux -L fm-lab rename-window -t primary:worker "fm-$ID"
printf '%s\n' "$ID" > "$LAB/id"
mkdir -p "$FM_HOME/data/$ID"
cat > "$FM_HOME/data/$ID/brief.md" <<EOF
# Task
## Captain's intent
Disposable lifecycle validation. Reply READY and then wait. Do not run any tool, edit any file, or launch any validation pipeline.
## Firstmate spec
No product work is required. Wait for the operator to tear down this disposable lab.
EOF
{
 printf 'window=primary:fm-%s\nendpoint_task_id=%s\nworktree=%s/wt\nproject=%s/repo\nharness=codex\nkind=ship\nmode=no-mistakes\nyolo=off\nmodel=default\neffort=default\nbackend=tmux\nx_request=lab-request\ndecisions_reviewed=1\npr=https://github.com/kunchenguid/firstmate/pull/7076\npr_head=6deb5a18c56b2f2fc935aa84540098dbdf0170d0\n' "$ID" "$ID" "$LAB" "$LAB"
} > "$FM_HOME/state/$ID.meta"
. bin/fm-pr-lib.sh
fm_pr_poll_prepare "$FM_HOME/state" "$ID" github https://github.com/kunchenguid/firstmate/pull/7076 github.com kunchenguid/firstmate 7076 "$ROOT/bin/fm-pr-poll.sh"
fm_pr_poll_publish_prepared
sha256sum "$FM_HOME/state/$ID.check.sh" "$FM_HOME/state/$ID.pr-poll" > "$LAB/before.hash"
echo 'BEFORE: existing watch accepted'
fm_pr_poll_snapshot_capture "$FM_HOME/state" "$ID" "$ROOT/bin/fm-pr-poll.sh"
touch "$FM_HOME/config/trace-context"
printf '%s\n' "$$" > "$FM_HOME/state/.lock"
printf '%s on\n' "$$" > "$FM_HOME/state/.trace-context-effective"
FM_SPAWN_NO_GUARD=1 FM_CONTROL_POLL=0.2 FM_CONTROL_EXIT_WAIT=15 FM_CONTROL_LAUNCH_WAIT=15 bin/fm-control.sh "$ID" relaunch --note 'Disposable validation only: reply READY then wait; do not use tools or change files.'
echo 'AFTER: persisted task metadata'
cat "$FM_HOME/state/$ID.meta"
fm_pr_poll_snapshot_capture "$FM_HOME/state" "$ID" "$ROOT/bin/fm-pr-poll.sh"
echo 'AFTER: existing watch accepted'
sha256sum "$FM_HOME/state/$ID.check.sh" "$FM_HOME/state/$ID.pr-poll" > "$LAB/after.hash"
cmp "$LAB/before.hash" "$LAB/after.hash"
echo 'AFTER: check and sidecar bytes unchanged'
