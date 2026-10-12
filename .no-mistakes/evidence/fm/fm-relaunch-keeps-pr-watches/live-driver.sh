#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4R8N97CBS9N6ZY181H93BN2
LAB=$(sed -n '1p' .validation-runtime/lab-paths)
SOCKET_DIR=$(sed -n '2p' .validation-runtime/lab-paths)
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS HERDR_ENV HERDR_PANE_ID HERDR_SESSION HERDR_SOCKET_PATH HERDR_TAB_ID HERDR_WORKSPACE_ID TASKS_AXI_FILE TASKS_AXI_BACKEND
export FM_HOME=$LAB TMUX_TMPDIR=$SOCKET_DIR TMUX=$(cat .validation-runtime/socket-identity)
export FM_CONTROL_EXIT_WAIT=20 FM_CONTROL_LAUNCH_WAIT=20 FM_CONTROL_POLL=0.5
STATE=$LAB/state
URL=https://github.com/cli/cli/pull/14634
{
  printf '%s\n' 'window=primary:fm-watch' 'endpoint_task_id=watch' "worktree=$LAB/projects/worker" "project=$LAB/projects/demo" 'harness=codex' 'kind=ship' 'mode=no-mistakes' 'yolo=off' 'branch=task-watch' 'model=default' 'effort=default' 'backend=tmux' 'decisions_reviewed=1' 'x_request=lab-request' "pr=$URL" 'pr_head=424f38df651e0b178d752073859af7ee1d3d02c3'
} > "$STATE/watch.meta"
printf '%s\n' "$$" > "$STATE/.lock"
touch "$LAB/config/trace-context"
printf '%s on\n' "$$" > "$STATE/.trace-context-effective"
. bin/fm-pr-lib.sh
fm_pr_poll_prepare "$STATE" watch github "$URL" github.com cli/cli 14634 "$ROOT/bin/fm-pr-poll.sh"
fm_pr_poll_publish_prepared
fm_pr_poll_snapshot_capture "$STATE" watch "$ROOT/bin/fm-pr-poll.sh"
echo 'Before relaunch: existing PR watch authenticated.'
sha256sum "$STATE/watch.check.sh" "$STATE/watch.pr-poll" "$STATE/watch.pr-poll-registration" > "$EVIDENCE/watch-artifacts-before.sha256"
tmux -L fm-lab capture-pane -p -t primary:fm-watch > "$EVIDENCE/worker-before.txt"
bin/fm-control.sh watch relaunch --harness codex --note 'Disposable lab: keep the PR merge watch; wait for instructions.'
fm_pr_poll_snapshot_capture "$STATE" watch "$ROOT/bin/fm-pr-poll.sh"
echo 'After real worker relaunch: same PR watch authenticated without re-registration.'
sha256sum "$STATE/watch.check.sh" "$STATE/watch.pr-poll" "$STATE/watch.pr-poll-registration" > "$EVIDENCE/watch-artifacts-after.sha256"
cmp "$EVIDENCE/watch-artifacts-before.sha256" "$EVIDENCE/watch-artifacts-after.sha256"
echo 'Check bytes, sidecar, and registration are unchanged.'
cat "$STATE/watch.meta" > "$EVIDENCE/task-after-relaunch.meta"
cat "$STATE/watch.control-relaunch" > "$EVIDENCE/relaunch-transaction.txt"
tmux -L fm-lab capture-pane -p -t primary:fm-watch > "$EVIDENCE/worker-after.txt"
cp "$STATE/watch.meta" "$LAB/valid-meta"
printf '%s\n' 'unknown_trailing_key=1' >> "$STATE/watch.meta"
if fm_pr_poll_snapshot_capture "$STATE" watch "$ROOT/bin/fm-pr-poll.sh"; then
  echo 'ERROR: unknown trailing metadata was accepted'; exit 1
fi
echo 'Unknown trailing metadata rejected by PR-watch authentication.'
FM_CHECK_INTERVAL=0 FM_POLL=1 timeout 30 bin/fm-watch.sh > "$EVIDENCE/unknown-trailing-watch.txt" 2>&1 || rc=$?
cat "$EVIDENCE/unknown-trailing-watch.txt"
cp "$LAB/valid-meta" "$STATE/watch.meta"
FM_CHECK_INTERVAL=0 FM_POLL=1 timeout 30 bin/fm-watch.sh > "$EVIDENCE/merged-watch.txt" 2>&1 || rc=$?
cat "$EVIDENCE/merged-watch.txt"
