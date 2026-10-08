#!/usr/bin/env bash
set -eu
LAB=$(cat .no-mistakes/readiness-lab.path)
export TMUX_TMPDIR="$LAB/tmux"
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4CC93HSD5MTCYJ23NN11EX3
cleanup() {
  command tmux -L fm-lab kill-server >/dev/null 2>&1 || true
  node -e 'require("fs").rmSync(process.argv[1], {recursive:true,force:true})' "$LAB"
}
trap cleanup EXIT
. bin/fm-tmux-lib.sh
tmux() { command tmux -L fm-lab "$@"; }
readiness() {
  local script=$1 target=${2:-primary} state result
  eval "$(sed -n '/^claude_ready_state()/,/^}/p' "$script")"
  result=0
  state=$(claude_ready_state fm-lab "$target") || result=$?
  printf '%s target=%s: %s exit=%s\n' "$script" "$target" "$state" "$result"
  return "$result"
}
for test in tests/fm-host-mirror-live-e2e.test.sh tests/fm-supervision-host-attended-live-e2e.test.sh; do
  readiness "$test"
done
command tmux -L fm-lab capture-pane -p -t primary > "$EVIDENCE/readiness-empty-screen.txt"
command tmux -L fm-lab send-keys -t primary -l 'Unsubmitted lab draft'
sleep 1
for test in tests/fm-host-mirror-live-e2e.test.sh tests/fm-supervision-host-attended-live-e2e.test.sh; do
  if readiness "$test"; then echo 'FAIL: pending draft accepted'; exit 1; fi
done
command tmux -L fm-lab capture-pane -p -t primary > "$EVIDENCE/readiness-pending-screen.txt"
command tmux -L fm-lab send-keys -t primary C-u
sleep 1
for test in tests/fm-host-mirror-live-e2e.test.sh tests/fm-supervision-host-attended-live-e2e.test.sh; do
  readiness "$test"
  if readiness "$test" missing; then echo 'FAIL: missing pane accepted'; exit 1; fi
done
command tmux -L fm-lab send-keys -t primary -l 'This is an isolated test. Use no tools. List numbers 1 through 5000, one per line.'
sleep 1
command tmux -L fm-lab send-keys -t primary Enter
seen=0
for i in $(seq 1 400); do
  state=$(fm_pane_busy_state primary claude)
  if [ "$state" = busy ]; then
    seen=1
    for test in tests/fm-host-mirror-live-e2e.test.sh tests/fm-supervision-host-attended-live-e2e.test.sh; do
      if readiness "$test"; then echo 'FAIL: busy model accepted'; exit 1; fi
    done
    command tmux -L fm-lab capture-pane -p -t primary > "$EVIDENCE/readiness-busy-screen.txt"
    break
  fi
  sleep 0.1
done
[ "$seen" = 1 ] || { command tmux -L fm-lab capture-pane -p -t primary > "$EVIDENCE/readiness-no-busy-screen.txt"; echo 'FAIL: no actual busy state observed'; exit 1; }
command tmux -L fm-lab send-keys -t primary Escape
printf '%s\n' 'PASS: both readiness guards accept idle/empty and reject draft, busy Claude, and missing pane.'
