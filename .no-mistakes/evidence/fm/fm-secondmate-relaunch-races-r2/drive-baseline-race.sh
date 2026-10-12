#!/usr/bin/env bash
set -eu
ROOT=$PWD
E=/home/denguinho/.no-mistakes/evidence/01M4RAVP51BZSKS54TT4H7KV5N/baseline
mkdir -p "$E"
L=$(mktemp -d "$PWD/.gate-lab.XXXXXX")
SOCK=''
cleanup() {
  [ -z "$SOCK" ] || TMUX_TMPDIR="$SOCK" tmux -L fm-lab kill-server 2>/dev/null || true
  [ -z "$SOCK" ] || "$ROOT/bin/fm-lab-home.sh" teardown "$L/primary" || true
  chmod -R u+w "$L"
  rm -rf "$L"
}
trap cleanup EXIT
mkdir "$L/runtime"
git archive 20dcbf91520b1816663b81873ad67d0b93b3e4d6 | tar -x -C "$L/runtime"
"$ROOT/bin/fm-lab-home.sh" create "$L/primary" >/dev/null
SOCK=$("$ROOT/bin/fm-lab-home.sh" tmux-dir "$L/primary")
export TMUX_TMPDIR="$SOCK" FM_HOME="$L/primary" FM_BACKEND=tmux FM_SKIP_SECONDMATE_SYNC=1
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
printf 'codex\n' > "$FM_HOME/config/secondmate-harness"
tmux -L fm-lab new-session -d -s firstmate -x 120 -y 40 'sleep 600'
tmux -L fm-lab set-option -g default-shell /bin/bash
tmux -L fm-lab set-option -g default-command "bash --noprofile --norc"
export TMUX=$(tmux -L fm-lab display-message -p '#{socket_path}'),1,0
for id in sm1 sm2 sm3 sm4; do
  mkdir -p "$L/$id"/{bin,state,data,config,projects}
  cp "$ROOT/AGENTS.md" "$L/$id/AGENTS.md"
  printf '%s\n' "$id" > "$L/$id/.fm-secondmate-home"
  printf 'Disposable validation home. Wait for operator input. Do not run commands or change files.\n' > "$L/$id/data/charter.md"
  printf 'window=firstmate:fm-%s\nbackend=tmux\nkind=secondmate\nharness=codex\nhome=%s\n' "$id" "$L/$id" > "$FM_HOME/state/$id.meta"
done
export FM_ROOT="$L/runtime" STATE="$FM_HOME/state"
pids=()
for id in sm1 sm2 sm3 sm4; do
 (
  . "$FM_ROOT/bin/fm-secondmate-liveness-lib.sh"
  fm_secondmate_liveness_lock "$id"
  trap 'fm_secondmate_liveness_unlock "$id"' EXIT
  fm_secondmate_liveness_probe "$STATE/$id.meta" "$id" poll
  printf 'before=%s\n' "$FM_SM_LIVE_STATE"
  rc=0; fm_secondmate_liveness_relaunch "$STATE/$id.meta" "$id" 60 || rc=$?
  printf 'rc=%s output=%s\n' "$rc" "$FM_SM_LIVE_OUT"
  cat "$STATE/.secondmate-relaunch-$id"
  exit "$rc"
 ) > "$E/relaunch-$id.log" 2>&1 & pids+=("$!")
done
rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
sleep 5
tmux -L fm-lab list-windows -F '#{window_name}: #{pane_current_command}' > "$E/live-endpoints.log"
for id in sm1 sm2 sm3 sm4; do
 tmux -L fm-lab capture-pane -p -t "firstmate:fm-$id" > "$E/pane-$id.log" 2>&1 || true
done
cat "$E/live-endpoints.log"
cat "$E/relaunch-sm1.log"
exit "$rc"
