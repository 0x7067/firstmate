#!/usr/bin/env bash
set -eu
ROOT=$PWD
W=$(mktemp -d "$PWD/.phase-tmp/rollout.XXXXXX")
trap 'rm -rf "$W"' EXIT
export TMPDIR="$W" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=Lab GIT_AUTHOR_EMAIL=lab@example.invalid GIT_COMMITTER_NAME=Lab GIT_COMMITTER_EMAIL=lab@example.invalid
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
mkdir "$W/home"
"$ROOT/bin/fm-lab-home.sh" create "$W/home" >/dev/null
cp -R "$ROOT/bin" "$W/home/"
printf 'lab\n' > "$W/home/AGENTS.md"
printf 'state/\ndata/\nconfig/\nprojects/\n.fm-lab-home\n' > "$W/home/.gitignore"
for file in fm-update.sh fm-ff-lib.sh fm-bootstrap.sh fm-remote-secondmate-control.sh; do
  git -C "$ROOT" show "20dcbf91520b1816663b81873ad67d0b93b3e4d6:bin/$file" > "$W/home/bin/$file"
done
printf '\n' >> "$W/home/bin/fm-pr-poll.sh"
printf 'manual\n' > "$W/home/config/backlog-backend"
touch "$W/home/state/.last-watcher-beat"
git init -q -b main "$W/home"
git -C "$W/home" add .
git -C "$W/home" commit -qm old-release
git init -q --bare "$W/origin.git"
git -C "$W/origin.git" symbolic-ref HEAD refs/heads/main
git -C "$W/home" remote add origin "$W/origin.git"
git -C "$W/home" push -q -u origin main
git -C "$W/home" remote set-head origin main
. "$ROOT/bin/fm-pr-lib.sh"
printf 'pr=https://github.com/lab/repo/pull/1\n' > "$W/home/state/valid.meta"
chmod 600 "$W/home/state/valid.meta"
fm_pr_poll_prepare "$W/home/state" valid github https://github.com/lab/repo/pull/1 github.com lab/repo 1 "$W/home/bin/fm-pr-poll.sh"
fm_pr_poll_publish_prepared
git clone -q "$W/origin.git" "$W/seed"
cp -R "$ROOT/bin/." "$W/seed/bin/"
git -C "$W/seed" add .
git -C "$W/seed" commit -qm migration-release
git -C "$W/seed" push -q origin main
printf '\nOLD UPDATER INSTALLS RELEASE\n'
FM_HOME="$W/home" "$W/home/bin/fm-update.sh"
! fm_pr_poll_artifacts_valid "$W/home/state" valid "$W/home/bin/fm-pr-poll.sh"
printf 'Watch remains stale before documented one-time session start.\n'
printf '\nDOCUMENTED ONE-TIME SESSION START\n'
FM_HOME="$W/home" "$W/home/bin/fm-session-start.sh" > "$W/session-start.txt" 2>&1
cat "$W/session-start.txt"
fm_pr_poll_artifacts_valid "$W/home/state" valid "$W/home/bin/fm-pr-poll.sh"
printf '\nWatch authenticated after one-time session start without a second update.\n'
