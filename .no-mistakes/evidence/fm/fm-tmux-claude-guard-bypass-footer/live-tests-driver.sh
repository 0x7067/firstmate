#!/usr/bin/env bash
set -u
export EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4CC93HSD5MTCYJ23NN11EX3
export TMPDIR="$PWD/.live-test-tmp"
export TMUX_TMPDIR=/tmp
unset FM_HOME FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_CONFIG_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS NO_MISTAKES_GATE
rm() {
  local arg
  for arg in "$@"; do
    case "$arg" in "$HOME/.claude/projects/"*) printf 'Boundary: retained disposable Claude transcript at %s\n' "$arg" >&2; return 0 ;; esac
  done
  command rm "$@"
}
tmux() {
  local result code
  result=$(command tmux "$@"); code=$?
  case " $* " in *' capture-pane '*) printf '%s\n' "$result" > "$EVIDENCE/${LIVE_LABEL}-last-pane.txt" ;; esac
  printf '%s\n' "$result"
  return "$code"
}
export -f rm tmux
export LIVE_LABEL=mirror
FM_HOST_MIRROR_LIVE_E2E=1 FM_HOST_MIRROR_LIVE_HARNESSES=claude bash tests/fm-host-mirror-live-e2e.test.sh > "$EVIDENCE/mirror-live.log" 2>&1
code=$?
cat "$EVIDENCE/mirror-live.log"
printf 'mirror exit=%s\n' "$code"
export LIVE_LABEL=attended
FM_SUPERVISION_HOST_ATTENDED_LIVE_E2E=1 bash tests/fm-supervision-host-attended-live-e2e.test.sh > "$EVIDENCE/attended-live.log" 2>&1
code=$?
cat "$EVIDENCE/attended-live.log"
printf 'attended exit=%s\n' "$code"
