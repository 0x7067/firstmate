#!/usr/bin/env bash
set -eu
ROOT=$PWD
. tests/lib.sh
. tests/herdr-test-safety.sh
herdr_forget_inherited_pane
export SHELL=/bin/sh
export FM_HOME="$PWD/.validation/live-home"
export FM_HERDR_LAB_STATE_DIR="$PWD/.validation/herdr-state"
mkdir -p "$FM_HOME/state" "$FM_HOME/config" "$FM_HOME/data" "$FM_HOME/projects"
SESSION=$(bin/fm-herdr-lab.sh name processwalk)
export HERDR_SESSION=$SESSION
cleanup() { bin/fm-herdr-lab.sh teardown "$SESSION"; }
trap cleanup EXIT
bin/fm-herdr-lab.sh provision "$SESSION"
. bin/fm-backend.sh
fm_backend_source herdr
container=$(fm_backend_herdr_container_ensure "$PWD")
ids=$(fm_backend_herdr_create_task "${container%%$'\t'*}" processwalk "$PWD" "${container#*$'\t'}")
read -r TAB PANE <<< "$ids"
standin=$(fm_agent_standin "$PWD/.validation/standin")
for suffix in plain 'Application Support/Some Dir'; do
  dir="$PWD/.validation/$suffix"
  mkdir -p "$dir"
  ln -sf "$standin" "$dir/pi"
  printf -v command '%q 300 & echo CHILD=$!' "$dir/pi"
  bin/fm-herdr-lab.sh run "$SESSION" pane send-text "$PANE" "$command"
  bin/fm-herdr-lab.sh run "$SESSION" pane send-keys "$PANE" enter
  sleep 0.5
  info=$(bin/fm-herdr-lab.sh run "$SESSION" pane process-info --pane "$PANE")
  printf 'CASE=%s\nPROCESS-INFO=%s\n' "$suffix" "$info"
  shell_pid=$(jq -r '.result.process_info.shell_pid' <<< "$info")
  ps -o pid=,ppid=,comm=,args= --ppid "$shell_pid"
  process=$(fm_backend_herdr_pane_process_state "$SESSION" "$PANE")
  [ "$process" = agent ] || { echo "Expected agent, got $process"; exit 1; }
  bin/fm-herdr-lab.sh run "$SESSION" pane report-agent "$PANE" --source processwalk --agent pi --state idle
  state=$(fm_backend_agent_state herdr "$SESSION:$PANE")
  printf 'background descendant process=%s registered state=%s\n' "$process" "$state"
  [ "$state" = alive ]
  pkill -P "$shell_pid"
  bin/fm-herdr-lab.sh run "$SESSION" pane send-text "$PANE" ":"
  bin/fm-herdr-lab.sh run "$SESSION" pane send-keys "$PANE" enter
  sleep 0.3
  process=$(fm_backend_herdr_pane_process_state "$SESSION" "$PANE")
  state=$(fm_backend_agent_state herdr "$SESSION:$PANE")
  printf 'childless control process=%s registered state=%s\n' "$process" "$state"
  [ "$process" = shell ] || exit 1
  [ "$state" = dead ] || exit 1
done
