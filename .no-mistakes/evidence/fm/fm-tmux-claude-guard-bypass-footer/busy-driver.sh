#!/usr/bin/env bash
set -u
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4CC93HSD5MTCYJ23NN11EX3
LAB=$(mktemp -d "$PWD/.live-test-tmp/guard.XXXXXX")
bin/fm-lab-home.sh create "$LAB" >/dev/null
SOCKDIR=$(bin/fm-lab-home.sh tmux-dir "$LAB")
cleanup() { TMUX_TMPDIR="$SOCKDIR" command tmux -L fm-lab kill-server 2>/dev/null || true; bin/fm-lab-home.sh teardown "$LAB"; rm -rf "$LAB"; }
trap cleanup EXIT
unset FM_HOME FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS NO_MISTAKES_GATE
while IFS= read -r name; do unset "$name"; done < <(env | grep -E '^(CLAUDECODE|CLAUDE_CODE_[A-Z_]+|CLAUDE_PID|CLAUDE_EFFORT)=' | cut -d= -f1)
export TMUX_TMPDIR="$SOCKDIR"
command tmux -L fm-lab new-session -d -s primary -x 160 -y 40 -c "$PWD" -e FM_HOME="$LAB" -e CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false 'claude --permission-mode auto --model haiku'
. bin/fm-tmux-lib.sh
tmux() { command tmux -L fm-lab "$@"; }
# Execute the readiness functions as shipped, against the real primary.
for file in tests/fm-host-mirror-live-e2e.test.sh tests/fm-supervision-host-attended-live-e2e.test.sh; do
  eval "$(sed -n '/^claude_ready_state() {/,/^}/p' "$file")"
  printf 'Testing %s readiness interface\n' "$file"
  for ((i=0;i<60;i++)); do
    screen=$(command tmux -L fm-lab capture-pane -p -t primary)
    case "$screen" in
      *'Yes, I trust this folder'*) command tmux -L fm-lab send-keys -t primary Enter; sleep 3 ;;
      *'Allow external CLAUDE.md file imports?'*) command tmux -L fm-lab send-keys -t primary Enter; sleep 3 ;;
      *) if out=$(claude_ready_state fm-lab primary); then break; fi ;;
    esac
    sleep 1
  done
  [ "$i" -lt 60 ] || { printf 'FAIL readiness timed out: %s\n%s\n' "$out" "$screen"; exit 1; }
  printf 'idle auto-mode composer: %s\n' "$out"
  command tmux -L fm-lab capture-pane -p -t primary > "$EVIDENCE/guard-auto-idle.txt"
  command tmux -L fm-lab send-keys -t primary -l 'unsent captain draft'
  sleep 1
  if out=$(claude_ready_state fm-lab primary); then printf 'FAIL accepted unsent draft: %s\n' "$out"; exit 1; fi
  printf 'unsent draft rejected: %s\n' "$out"
  command tmux -L fm-lab capture-pane -p -t primary > "$EVIDENCE/guard-pending.txt"
  command tmux -L fm-lab send-keys -t primary C-u
  sleep 1
  out=$(claude_ready_state fm-lab primary) || { printf 'FAIL did not recover empty composer: %s\n' "$out"; exit 1; }
  printf 'cleared draft accepted: %s\n' "$out"
  if out=$(claude_ready_state fm-lab missing-pane); then printf 'FAIL accepted missing pane\n'; exit 1; fi
  printf 'missing pane rejected: %s\n' "$out"
  command tmux -L fm-lab send-keys -t primary -l 'Use no tools. Write one hundred numbered sentences about clouds.'
  command tmux -L fm-lab send-keys -t primary Enter
  seen=0
  for ((j=0;j<100;j++)); do
    out=$(claude_ready_state fm-lab primary); code=$?
    case "$out" in busy=busy*)
      [ "$code" -ne 0 ] || { echo 'FAIL accepted busy agent'; exit 1; }
      printf 'active model turn rejected: %s\n' "$out"
      command tmux -L fm-lab capture-pane -p -t primary > "$EVIDENCE/guard-busy.txt"
      seen=1; break ;;
    esac
    sleep 0.1
  done
  [ "$seen" = 1 ] || { printf 'FAIL could not observe busy turn: %s\n' "$out"; exit 1; }
  command tmux -L fm-lab send-keys -t primary Escape
  sleep 3
done
