#!/usr/bin/env bash
set -euo pipefail
LAB=$(sed -n '1p' .validation-runtime/lab-paths)
SOCKET_DIR=$(sed -n '2p' .validation-runtime/lab-paths)
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4R8N97CBS9N6ZY181H93BN2
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS HERDR_ENV HERDR_PANE_ID HERDR_SESSION HERDR_SOCKET_PATH HERDR_TAB_ID HERDR_WORKSPACE_ID TASKS_AXI_FILE TASKS_AXI_BACKEND
export FM_HOME=$LAB TMUX_TMPDIR=$SOCKET_DIR TMUX=$(cat .validation-runtime/socket-identity)
export FM_CONTROL_EXIT_WAIT=20 FM_CONTROL_LAUNCH_WAIT=20 FM_CONTROL_POLL=0.5
. bin/fm-pr-lib.sh
STATE=$LAB/state
URL=https://github.com/cli/cli/pull/14634
fm_pr_poll_prepare "$STATE" watch github "$URL" github.com cli/cli 14634 "$PWD/bin/fm-pr-poll.sh"
fm_pr_poll_publish_prepared
fm_pr_poll_snapshot_capture "$STATE" watch "$PWD/bin/fm-pr-poll.sh"
echo 'Prepared a new registered watch before the trace-disabled relaunch.'
sha256sum "$STATE/watch.check.sh" "$STATE/watch.pr-poll" "$STATE/watch.pr-poll-registration" > "$LAB/before-disabled.sha256"
rm -f "$LAB/config/trace-context"
printf '%s\n' "$$" > "$STATE/.lock"
printf '%s off\n' "$$" > "$STATE/.trace-context-effective"
bin/fm-control.sh watch relaunch --harness codex --note 'Disposable lab: tracing is disabled. Reply READY and wait; use no tools.'
fm_pr_poll_snapshot_capture "$STATE" watch "$PWD/bin/fm-pr-poll.sh"
sha256sum "$STATE/watch.check.sh" "$STATE/watch.pr-poll" "$STATE/watch.pr-poll-registration" > "$LAB/after-disabled.sha256"
cmp "$LAB/before-disabled.sha256" "$LAB/after-disabled.sha256"
! grep -q '^traceparent=' "$STATE/watch.meta"
echo 'Trace-disabled relaunch: existing PR watch accepted, bytes unchanged, previous trace carrier cleared.'
cat "$STATE/watch.meta" > "$EVIDENCE/task-after-disabled-relaunch.meta"
cat "$STATE/watch.control-relaunch" > "$EVIDENCE/disabled-relaunch-transaction.txt"
tmux -L fm-lab capture-pane -p -t primary:fm-watch > "$EVIDENCE/worker-disabled-after.txt"
