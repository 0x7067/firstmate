#!/usr/bin/env bash
set -eu
ROOT=$PWD
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4RF1XCBWMY5KDPKASH524ZJ
LAB=$(mktemp -d "$PWD/.nm-race.XXXXXX")
SOCKET_DIR=''
cleanup() {
  [ -z "$SOCKET_DIR" ] || TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab kill-server 2>/dev/null || true
  [ -z "$SOCKET_DIR" ] || bin/fm-lab-home.sh teardown "$LAB/main" || true
  rm -rf "$LAB"
}
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB/main" >/dev/null
SOCKET_DIR=$(bin/fm-lab-home.sh tmux-dir "$LAB/main")
mkdir -p "$LAB/code"
cp -a bin "$LAB/code/bin"
if [ "${1:-target}" = base ]; then git show 20dcbf91520b1816663b81873ad67d0b93b3e4d6:bin/fm-secondmate-liveness-lib.sh > "$LAB/code/bin/fm-secondmate-liveness-lib.sh"; fi
export FM_HOME="$LAB/main" FM_ROOT="$LAB/code" STATE="$LAB/main/state" FM_BACKEND=tmux
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
printf 'codex\n' > "$FM_HOME/config/secondmate-harness"
touch "$FM_HOME/config/keep-ai-trailers"
# Private primary uses the installed real CLI and the normal login; no input is sent.
env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab new-session -d -x 120 -y 40 -s primary -c "$ROOT" -e FM_HOME="$FM_HOME" codex
TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab set-option -g default-command "bash --noprofile --norc"
export TMUX
TMUX=$(TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab display-message -p -t primary '#{socket_path},#{pid},0')
exec > >(tee "$EVIDENCE/live-race-${1:-target}.log") 2>&1
for id in one two three four; do
  home="$LAB/$id"
  mkdir -p "$home/bin" "$home/data" "$home/state" "$home/config" "$home/projects"
  printf '%s\n' "$id" > "$home/.fm-secondmate-home"
  ln -s "$ROOT/AGENTS.md" "$home/AGENTS.md"
  printf 'Disposable validation home. Stay idle. Do not use tools or change files.\n' > "$home/data/charter.md"
  git -C "$home" init -q -b main
  cat > "$STATE/$id.meta" <<EOF
kind=secondmate
harness=codex
backend=tmux
window=primary:fm-$id
home=$home
EOF
done
# Four real library recovery processes compete at once, exactly as the sweep does.
for id in one two three four; do
  (
    . "$FM_ROOT/bin/fm-secondmate-liveness-lib.sh"
    meta="$STATE/$id.meta"
    fm_secondmate_liveness_lock "$id"
    fm_secondmate_liveness_probe "$meta" "$id" poll
    echo "$id probe=$FM_SM_LIVE_STATE status=$FM_SM_LIVE_STATUS"
    rc=0
    fm_secondmate_liveness_relaunch "$meta" "$id" 30 || rc=$?
    printf '%s recovery rc=%s\n%s\n' "$id" "$rc" "$FM_SM_LIVE_OUT"
    fm_secondmate_liveness_unlock "$id"
    exit "$rc"
  ) > "$LAB/$id.log" 2>&1 &
  printf '%s\n' "$!" >> "$LAB/pids"
done
rc=0
while read -r pid; do wait "$pid" || rc=1; done < "$LAB/pids"
for id in one two three four; do cat "$LAB/$id.log"; cat "$STATE/.secondmate-relaunch-$id"; done
TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab list-windows -t primary -F '#{window_name} #{pane_current_command} #{pane_width}x#{pane_height}'
sleep 5
for id in one two three four; do
  echo "PANE $id"
  TMUX_TMPDIR="$SOCKET_DIR" tmux -L fm-lab capture-pane -p -t "primary:fm-$id" || true
done
if [ "${1:-target}" = target ]; then
  . "$FM_ROOT/bin/fm-secondmate-liveness-lib.sh"
  for id in one two three four; do
    fm_secondmate_liveness_probe "$STATE/$id.meta" "$id" poll
    printf "Post-launch %s state=%s status=%s\n" "$id" "$FM_SM_LIVE_STATE" "$FM_SM_LIVE_STATUS"
    [ "$FM_SM_LIVE_STATE" = alive ]
  done
fi
exit "$rc"
