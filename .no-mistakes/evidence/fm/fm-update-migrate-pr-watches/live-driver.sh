#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
MODE=${MODE:-current}
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4RGADZCQ2ZP4DVYY9FKMAEX
WORLD=$(mktemp -d "$ROOT/.phase-tmp/live.XXXXXX")
trap 'rm -rf "$WORLD"' EXIT
export TMPDIR="$WORLD" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Lab GIT_AUTHOR_EMAIL=lab@example.invalid GIT_COMMITTER_NAME=Lab GIT_COMMITTER_EMAIL=lab@example.invalid
unset FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS TASKS_AXI_FILE TASKS_AXI_BACKEND
mkdir "$WORLD/tmux"
export TMUX_TMPDIR="$WORLD/tmux"
git init -q -b main "$WORLD/seed"
cp -R bin "$WORLD/seed/"
if [ "$MODE" = rollout ]; then
  for file in fm-update.sh fm-ff-lib.sh fm-bootstrap.sh fm-remote-secondmate-control.sh; do
    git show "20dcbf91520b1816663b81873ad67d0b93b3e4d6:bin/$file" > "$WORLD/seed/bin/$file"
  done
fi
git show HEAD:AGENTS.md > "$WORLD/seed/AGENTS.md"
printf 'state/\ndata/\nconfig/\nprojects/\n.fm-*\n' > "$WORLD/seed/.gitignore"
printf '\n# Historical generation\n' >> "$WORLD/seed/bin/fm-pr-poll.sh"
git -C "$WORLD/seed" add .
git -C "$WORLD/seed" commit -qm historical
git clone -q --bare "$WORLD/seed" "$WORLD/origin.git"
for role in primary local remote; do
  home="$WORLD/$role"
  bash bin/fm-lab-home.sh create "$home" >/dev/null
  git -C "$home" init -q -b main
  git -C "$home" remote add origin "$WORLD/origin.git"
  git -C "$home" fetch -q origin
  git -C "$home" reset -q --hard origin/main
  git -C "$home" branch --set-upstream-to=origin/main main >/dev/null
  git -C "$home" remote set-head origin main
  [ "$role" = primary ] || { git -C "$home" checkout -q --detach; printf '%s\n' "$role" > "$home/.fm-secondmate-home"; }
  printf 'manual\n' > "$home/config/backlog-backend"
  for task in valid tampered; do
    printf 'pr=https://github.com/o/r/pull/1\n' > "$home/state/$task.meta"
    chmod 600 "$home/state/$task.meta"
    (
      . "$ROOT/bin/fm-pr-lib.sh"
      fm_pr_poll_prepare "$home/state" "$task" github https://github.com/o/r/pull/1 github.com o/r 1 "$home/bin/fm-pr-poll.sh"
      fm_pr_poll_publish_prepared
    )
  done
  printf '\n' >> "$home/state/tampered.check.sh"
  cp "$home/state/valid.meta" "$WORLD/$role-meta-before"
  cp "$home/state/tampered.check.sh" "$WORLD/$role-tampered-before"
done
printf -- '- local - local domain (home: %s/local; scope: things; projects: p; added 2026-10-16)\n' "$WORLD" > "$WORLD/primary/data/secondmates.md"
cp "$ROOT/bin/fm-pr-poll.sh" "$WORLD/seed/bin/fm-pr-poll.sh"
for file in fm-update.sh fm-ff-lib.sh fm-bootstrap.sh fm-remote-secondmate-control.sh; do
  cp "$ROOT/bin/$file" "$WORLD/seed/bin/$file"
done
git -C "$WORLD/seed" add .
git -C "$WORLD/seed" commit -qm current
git -C "$WORLD/seed" push -q "$WORLD/origin.git" main
echo '$ FM_HOME=<primary> bin/fm-update.sh'
FM_HOME="$WORLD/primary" FM_ROOT_OVERRIDE="$WORLD/primary" bash "$WORLD/primary/bin/fm-update.sh"
echo '$ FM_HOME=<remote> bin/fm-remote-secondmate-control.sh sync remote'
FM_HOME="$WORLD/remote" FM_ROOT_OVERRIDE="$WORLD/primary" bash "$WORLD/remote/bin/fm-remote-secondmate-control.sh" sync remote
if [ "$MODE" = rollout ]; then
  for role in primary local remote; do
    home="$WORLD/$role"
    (
      . "$ROOT/bin/fm-pr-lib.sh"
      fm_pr_poll_artifacts_registered_valid "$home/state" valid
      ! fm_pr_poll_artifacts_valid "$home/state" valid "$home/bin/fm-pr-poll.sh"
    )
    echo "$role: old updater installed the new release; intact historical watch still awaits the documented one-time step"
    FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_BOOTSTRAP_DETECT_ONLY=1 FM_BOOTSTRAP_NETWORK=skip bash "$home/bin/fm-bootstrap.sh" > "$EVIDENCE/live-readonly-$role.log" 2>&1
    (
      . "$ROOT/bin/fm-pr-lib.sh"
      ! fm_pr_poll_artifacts_valid "$home/state" valid "$home/bin/fm-pr-poll.sh"
    )
    echo "$role: detect-only startup left the historical registration unchanged"
    echo '$ FM_HOME=<'"$role"'> bin/fm-session-start.sh # documented one-time step'
    FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_SESSION_START_TIMEOUT=45 bash "$home/bin/fm-session-start.sh" > "$EVIDENCE/live-rollout-start-$role.log" 2>&1
    sed -n '6,8p' "$EVIDENCE/live-rollout-start-$role.log"
  done
fi
for role in primary local remote; do
  home="$WORLD/$role"
  (
    . "$ROOT/bin/fm-pr-lib.sh"
    fm_pr_poll_artifacts_valid "$home/state" valid "$home/bin/fm-pr-poll.sh"
    ! fm_pr_poll_artifacts_valid "$home/state" tampered "$home/bin/fm-pr-poll.sh"
  )
  cmp "$home/state/valid.meta" "$WORLD/$role-meta-before"
  cmp "$home/state/tampered.check.sh" "$WORLD/$role-tampered-before"
  echo "$role: current watch authenticates; altered watch remains refused; task metadata and refused program unchanged"
done
if [ "$MODE" = rollout ]; then exit 0; fi
home="$WORLD/primary"
cp "$home/bin/fm-pr-poll.sh" "$WORLD/old-poll"
printf '\n# Previous poll bytes\n' >> "$WORLD/old-poll"
(
  . "$ROOT/bin/fm-pr-lib.sh"
  fm_pr_poll_prepare "$home/state" valid github https://github.com/o/r/pull/1 github.com o/r 1 "$WORLD/old-poll"
  fm_pr_poll_publish_prepared
  device=$(fm_pr_file_device "$home/state")
  awk -v device="$device" -v shifted="$((device+1))" 'NR == 10 || NR == 11 { sub("^" device ":", shifted ":") } {print}' "$home/state/valid.pr-poll-registration" > "$WORLD/shifted"
  chmod 600 "$WORLD/shifted"
  mv "$WORLD/shifted" "$home/state/valid.pr-poll-registration"
)
echo '$ FM_HOME=<primary> bin/fm-pr-check.sh migrate-all # historical poll plus renumbered device'
rc=0
FM_HOME="$home" FM_ROOT_OVERRIDE="$home" bash "$home/bin/fm-pr-check.sh" migrate-all || rc=$?
[ "$rc" = 1 ] # the intentionally altered sibling remains refused
(
  . "$ROOT/bin/fm-pr-lib.sh"
  fm_pr_poll_artifacts_valid "$home/state" valid "$home/bin/fm-pr-poll.sh"
)
echo 'renumbered device: intact historical watch authenticates against current poll after migration'
echo '$ FM_HOME=<primary> bin/fm-update.sh # repeat'
FM_HOME="$WORLD/primary" FM_ROOT_OVERRIDE="$WORLD/primary" bash "$ROOT/bin/fm-update.sh"
echo '$ FM_HOME=<remote> bin/fm-remote-secondmate-control.sh sync remote # repeat'
FM_HOME="$WORLD/remote" FM_ROOT_OVERRIDE="$WORLD/primary" bash "$ROOT/bin/fm-remote-secondmate-control.sh" sync remote
echo '$ FM_HOME=<primary> bin/fm-session-start.sh'
FM_HOME="$WORLD/primary" FM_ROOT_OVERRIDE="$WORLD/primary" FM_SESSION_START_TIMEOUT=45 bash "$ROOT/bin/fm-session-start.sh" > "$EVIDENCE/live-session-start.log" 2>&1
sed -n '1,12p' "$EVIDENCE/live-session-start.log"
