#!/usr/bin/env bash
set -eu
ROOT=$PWD
W=$(mktemp -d "$PWD/.phase-tmp/live.XXXXXX")
trap 'rm -rf "$W"' EXIT
export TMPDIR="$W" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=Lab GIT_AUTHOR_EMAIL=lab@example.invalid GIT_COMMITTER_NAME=Lab GIT_COMMITTER_EMAIL=lab@example.invalid
unset FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
. "$ROOT/bin/fm-pr-lib.sh"
git init -q --bare "$W/origin.git"
git -C "$W/origin.git" symbolic-ref HEAD refs/heads/main
git init -q -b main "$W/seed"
cp -R "$ROOT/bin" "$W/seed/"
printf 'lab\n' > "$W/seed/AGENTS.md"
printf 'state/\ndata/\nconfig/\nprojects/\n.fm-secondmate-home\n.fm-lab-home\n' > "$W/seed/.gitignore"
git -C "$ROOT" show 20dcbf91520b1816663b81873ad67d0b93b3e4d6:bin/fm-pr-poll.sh > "$W/seed/bin/fm-pr-poll.sh"
printf "\n" >> "$W/seed/bin/fm-pr-poll.sh"
git -C "$W/seed" add .
git -C "$W/seed" commit -qm old-poll
git -C "$W/seed" remote add origin "$W/origin.git"
git -C "$W/seed" push -q -u origin main
git clone -q "$W/origin.git" "$W/main"
git -C "$W/main" worktree add -q --detach "$W/local" HEAD
git clone -q "$W/origin.git" "$W/remote"
git -C "$W/remote" checkout -q --detach
mkdir "$W/home"
"$ROOT/bin/fm-lab-home.sh" create "$W/home" >/dev/null
for home in "$W/home" "$W/local" "$W/remote"; do
  mkdir -p "$home/state" "$home/data" "$home/config"
  printf 'manual\n' > "$home/config/backlog-backend"
  touch "$home/state/.last-watcher-beat"
  for id in valid invalid; do
    printf 'pr=https://github.com/lab/repo/pull/1\n' > "$home/state/$id.meta"
    chmod 600 "$home/state/$id.meta"
    fm_pr_poll_prepare "$home/state" "$id" github https://github.com/lab/repo/pull/1 github.com lab/repo 1 "$W/main/bin/fm-pr-poll.sh"
    fm_pr_poll_publish_prepared
  done
  printf '\n' >> "$home/state/invalid.check.sh"
  cp "$home/state/valid.meta" "$home/state/before-meta"
  cp "$home/state/invalid.check.sh" "$home/state/before-invalid"
done
printf 'local\n' > "$W/local/.fm-secondmate-home"
printf 'remote\n' > "$W/remote/.fm-secondmate-home"
printf -- '- local - local lab (home: %s/local; scope: lab; projects: lab; added 2026-10-12)\n' "$W" > "$W/home/data/secondmates.md"
cp "$ROOT/bin/fm-pr-poll.sh" "$W/seed/bin/fm-pr-poll.sh"
git -C "$W/seed" add bin/fm-pr-poll.sh
git -C "$W/seed" commit -qm new-poll
git -C "$W/seed" push -q origin main
printf '\nCURRENT UPDATER: PRIMARY AND REGISTRY-ONLY LOCAL HOME\n'
FM_HOME="$W/home" FM_ROOT_OVERRIDE="$W/main" "$W/main/bin/fm-update.sh"
printf '\nREMOTE HOST-LOCAL SYNC\n'
FM_HOME="$W/remote" FM_ROOT_OVERRIDE="$W/main" "$ROOT/bin/fm-remote-secondmate-control.sh" sync remote
printf '\nREPEAT REMOTE HOST-LOCAL SYNC\n'
FM_HOME="$W/remote" FM_ROOT_OVERRIDE="$W/main" "$ROOT/bin/fm-remote-secondmate-control.sh" sync remote
for home in "$W/home" "$W/local" "$W/remote"; do
  fm_pr_poll_artifacts_valid "$home/state" valid "$ROOT/bin/fm-pr-poll.sh"
  ! fm_pr_poll_artifacts_valid "$home/state" invalid "$ROOT/bin/fm-pr-poll.sh"
  cmp "$home/state/valid.meta" "$home/state/before-meta"
  cmp "$home/state/invalid.check.sh" "$home/state/before-invalid"
  printf '%s: valid watch authenticated; altered watch refused and untouched; metadata unchanged\n' "${home##*/}"
  rc=0
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-pr-check.sh" migrate-all || rc=$?
  [ "$rc" -eq 1 ]
done
printf '\nHISTORICAL WATCH WITH PREVIOUS DEVICE BINDINGS\n'
state="$W/home/state"
cp "$ROOT/bin/fm-pr-poll.sh" "$W/historical"
printf '\n' >> "$W/historical"
printf 'pr=https://github.com/lab/repo/pull/2\n' > "$state/remount.meta"
chmod 600 "$state/remount.meta"
fm_pr_poll_prepare "$state" remount github https://github.com/lab/repo/pull/2 github.com lab/repo 2 "$W/historical"
fm_pr_poll_publish_prepared
device=$(fm_pr_file_device "$state")
awk -v old="$device" -v other="$((device+1))" 'NR==10 || NR==11 {sub("^" old ":",other ":")} {print}' "$state/remount.pr-poll-registration" > "$state/.shift"
chmod 600 "$state/.shift"
mv "$state/.shift" "$state/remount.pr-poll-registration"
! fm_pr_poll_artifacts_registered_valid "$state" remount
rc=0
FM_HOME="$W/home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-pr-check.sh" migrate-all || rc=$?
[ "$rc" -eq 1 ]
fm_pr_poll_artifacts_valid "$state" remount "$ROOT/bin/fm-pr-poll.sh"
printf 'Historical watch authenticated after migration from previous device bindings.\n'
