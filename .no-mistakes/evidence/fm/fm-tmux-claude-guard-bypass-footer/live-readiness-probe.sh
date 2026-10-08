#!/usr/bin/env bash
set -eu
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4CHW5YHGMARGX7629WDRE4A
LAB=$(mktemp -d /tmp/fm-lab.XXXXXX)
bin/fm-lab-home.sh create "$LAB" >/dev/null
mkdir -p "$LAB/tmux"
cleanup() {
  TMUX_TMPDIR="$LAB/tmux" command tmux -L fm-lab kill-server 2>/dev/null || true
  rm -rf "$LAB"
}
trap cleanup EXIT
env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u CLAUDECODE \
  TMUX_TMPDIR="$LAB/tmux" CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false \
  tmux -L fm-lab new-session -d -s primary -x 200 -y 50 -c "$PWD" -e FM_HOME="$LAB" \
  'claude --model haiku --effort low --permission-mode auto --settings '\''{"disableAllHooks":true}'\'''
. bin/fm-tmux-lib.sh
tmux() { TMUX_TMPDIR="$LAB/tmux" command tmux -L fm-lab "$@"; }
ready() {
  busy=$(fm_pane_busy_state primary claude)
  composer=$(fm_tmux_composer_state primary)
  printf 'busy=%s composer=%s\n' "$busy" "$composer"
  [ "$busy" = idle ] && [ "$composer" = empty ]
}
for i in $(seq 1 90); do
  if ready > "$EVIDENCE/probe-initial-state.txt"; then break; fi
  sleep 1
done
ready
tmux capture-pane -p -t primary > "$EVIDENCE/probe-auto-idle-screen.txt"
tmux send-keys -t primary -l 'unsent captain draft'
sleep 1
if ready; then echo 'FAIL: accepted unsent input'; exit 1; fi
[ "$composer" = pending ] || [ "$composer" = pending-unproven ]
echo 'PASS: pending input blocks readiness'
tmux capture-pane -p -t primary > "$EVIDENCE/probe-pending-screen.txt"
tmux send-keys -t primary C-u
sleep 1
ready
tmux send-keys -t primary -l 'Reply with the integers from 1 to 100, one per line. Do not use tools.'
tmux send-keys -t primary Enter
found=0
for i in $(seq 1 60); do
  if ready > "$EVIDENCE/probe-turn-state.txt"; then :; else
    if [ "$busy" = busy ]; then found=1; break; fi
  fi
  sleep 0.1
done
cat "$EVIDENCE/probe-turn-state.txt"
[ "$found" = 1 ]
echo 'PASS: active Claude turn blocks readiness'
tmux capture-pane -p -t primary > "$EVIDENCE/probe-busy-screen.txt"
