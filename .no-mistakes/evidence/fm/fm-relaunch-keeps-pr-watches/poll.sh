#!/usr/bin/env bash
set -eu
LAB=$PWD/.live-pr-lab
export FM_HOME=$LAB/home TMUX_TMPDIR=$(cat "$LAB/socket-dir")
export TMUX=$(tmux -L fm-lab display-message -p -t primary '#{socket_path},#{pid},0')
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS HERDR_ENV HERDR_SESSION HERDR_PANE_ID
ID=$(cat "$LAB/id")
for meta in "$FM_HOME/state/"*.meta; do
 [ "$meta" = "$FM_HOME/state/$ID.meta" ] && continue
 old=$(basename "$meta" .meta)
 rm -f "$meta" "$FM_HOME/state/$old.check.sh" "$FM_HOME/state/$old.pr-poll" "$FM_HOME/state/$old.pr-poll-registration"
done
cp "$FM_HOME/state/$ID.meta" "$LAB/valid.meta"
printf 'unknown_trailing_key=1\n' >> "$FM_HOME/state/$ID.meta"
echo 'ADVERSARIAL: appended unknown key after PR identity'
FM_CHECK_INTERVAL=0 FM_POLL=0.1 FM_HEARTBEAT=999999 timeout 20 bin/fm-watch.sh
cp "$LAB/valid.meta" "$FM_HOME/state/$ID.meta"
echo 'RESTORED: same watch, valid relaunch metadata; querying actual merged GitHub PR'
FM_CHECK_INTERVAL=0 FM_POLL=0.1 FM_HEARTBEAT=999999 timeout 20 bin/fm-watch.sh
echo 'PERSISTED MERGE OUTCOME'
cat "$FM_HOME/state/$ID.status"
