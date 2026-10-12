#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4R5YM2H6A7K9P7MAV034931
WORLD=$(mktemp -d "$ROOT/.test-phase-tmp/live.XXXXXX")
trap 'rm -rf "$WORLD"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=lab GIT_AUTHOR_EMAIL=lab@example.invalid GIT_COMMITTER_NAME=lab GIT_COMMITTER_EMAIL=lab@example.invalid
unset FM_GATE_REFUSE_BYPASS FM_TEST_SEAM FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
export TMPDIR="$WORLD"
# An invalid private socket prevents any contact with the operator tmux server.
export TMUX="$WORLD/private-socket,0,0"
mkdir "$WORLD/seed"
git archive HEAD | tar -x -C "$WORLD/seed"
cp "$ROOT/bin/fm-pr-poll.sh" "$WORLD/current-poll"
git show '20dcbf91520b1816663b81873ad67d0b93b3e4d6^:bin/fm-pr-poll.sh' > "$WORLD/seed/bin/fm-pr-poll.sh"
printf '\nstate/\ndata/\nconfig/\n.fm-secondmate-home\n.fm-lab-home\n' >> "$WORLD/seed/.gitignore"
for file in fm-update.sh fm-ff-lib.sh fm-bootstrap.sh fm-remote-secondmate-control.sh; do
  git show "20dcbf91520b1816663b81873ad67d0b93b3e4d6:bin/$file" > "$WORLD/seed/bin/$file"
done
git init -q -b main "$WORLD/seed"
git -C "$WORLD/seed" add -A
git -C "$WORLD/seed" commit -qm historical-poll-release
git init -q --bare "$WORLD/origin.git"
git -C "$WORLD/origin.git" symbolic-ref HEAD refs/heads/main
git -C "$WORLD/seed" remote add origin "$WORLD/origin.git"
git -C "$WORLD/seed" push -q -u origin main
git clone -q "$WORLD/origin.git" "$WORLD/main"
git -C "$WORLD/main" worktree add -q --detach "$WORLD/local" HEAD
git clone -q "$WORLD/origin.git" "$WORLD/coderoot"
git clone -q "$WORLD/origin.git" "$WORLD/remote"
git -C "$WORLD/remote" checkout -q --detach
"$ROOT/bin/fm-lab-home.sh" create "$WORLD/home" >/dev/null
for home in "$WORLD/local" "$WORLD/remote"; do mkdir -p "$home/state" "$home/data" "$home/config"; done
printf 'local\n' > "$WORLD/local/.fm-secondmate-home"
printf 'remote\n' > "$WORLD/remote/.fm-secondmate-home"
printf -- '- local - test domain (home: %s/local; scope: test; projects: test; added 2026-10-12)\n' "$WORLD" > "$WORLD/home/data/secondmates.md"
. "$ROOT/bin/fm-pr-lib.sh"
for home in "$WORLD/home" "$WORLD/local" "$WORLD/remote"; do
  printf 'manual\n' > "$home/config/backlog-backend"
  for id in valid invalid remounted; do
    printf 'pr=https://github.com/example/disposable/pull/1\npr_head=0123456789abcdef0123456789abcdef01234567\n' > "$home/state/$id.meta"
    chmod 600 "$home/state/$id.meta"
    fm_pr_poll_prepare "$home/state" "$id" github https://github.com/example/disposable/pull/1 github.com example/disposable 1 "$WORLD/main/bin/fm-pr-poll.sh"
    fm_pr_poll_publish_prepared
  done
  printf 'github\nhttps://github.com/example/disposable/pull/2\ngithub.com\nexample/disposable\n2\n' > "$home/state/invalid.pr-poll"
  device=$(fm_pr_file_device "$home/state")
  awk -v d="$device" -v s="$((device+1))" 'NR==10 || NR==11 {sub("^"d":",s":")} {print}' "$home/state/remounted.pr-poll-registration" > "$home/state/shift"
  chmod 600 "$home/state/shift"
  mv "$home/state/shift" "$home/state/remounted.pr-poll-registration"
  cp "$home/state/valid.meta" "$home/state/meta-before"
  cp "$home/state/invalid.check.sh" "$home/state/invalid-before"
done
cp "$WORLD/current-poll" "$WORLD/seed/bin/fm-pr-poll.sh"
for file in fm-update.sh fm-ff-lib.sh fm-bootstrap.sh fm-remote-secondmate-control.sh; do
  cp "$ROOT/bin/$file" "$WORLD/seed/bin/$file"
done
git -C "$WORLD/seed" add bin
git -C "$WORLD/seed" commit -qm current-poll-release
git -C "$WORLD/seed" push -q origin main
printf '\n=== Primary and registry-only local update ===\n'
FM_HOME="$WORLD/home" FM_ROOT_OVERRIDE="$WORLD/main" "$WORLD/main/bin/fm-update.sh"
printf '\n=== Remote host-local update ===\n'
FM_HOME="$WORLD/remote" FM_ROOT_OVERRIDE="$WORLD/coderoot" "$WORLD/coderoot/bin/fm-remote-secondmate-control.sh" update remote
for home in "$WORLD/home" "$WORLD/local" "$WORLD/remote"; do
  code_root=$home
  [ "$home" != "$WORLD/home" ] || code_root="$WORLD/main"
  ! fm_pr_poll_artifacts_valid "$home/state" valid "$ROOT/bin/fm-pr-poll.sh"
  printf '%s: old loaded updater left intact historical bytes, as documented.\n' "${home##*/}"
  FM_HOME="$home" FM_ROOT_OVERRIDE="$code_root" FM_SESSION_START_TIMEOUT=45 "$code_root/bin/fm-session-start.sh" > "$EVIDENCE/rollout-${home##*/}-session-start.log" 2>&1
  fm_pr_poll_artifacts_valid "$home/state" valid "$ROOT/bin/fm-pr-poll.sh"
  fm_pr_poll_artifacts_valid "$home/state" remounted "$ROOT/bin/fm-pr-poll.sh"
  ! fm_pr_poll_artifacts_valid "$home/state" invalid "$ROOT/bin/fm-pr-poll.sh"
  cmp "$home/state/valid.meta" "$home/state/meta-before"
  cmp "$home/state/invalid.check.sh" "$home/state/invalid-before"
  printf '%s: current authenticated valid and remounted watches; altered watch refused; metadata preserved\n' "${home##*/}"
  rc=0
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-pr-check.sh" migrate-all || rc=$?
  [ "$rc" = 1 ]
done
printf '\n=== Startup recovery through real session-start ===\n'
HOME_LAB="$WORLD/home"
# Reset just the generated watch to historical bytes using the registration publisher.
fm_pr_poll_prepare "$HOME_LAB/state" valid github https://github.com/example/disposable/pull/1 github.com example/disposable 1 "$WORLD/remote/state/invalid.check.sh"
fm_pr_poll_publish_prepared
FM_HOME="$HOME_LAB" FM_ROOT_OVERRIDE="$ROOT" FM_BOOTSTRAP_NETWORK=skip FM_BOOTSTRAP_DETECT_ONLY=1 "$ROOT/bin/fm-bootstrap.sh" > "$EVIDENCE/rollout-detect-only.log" 2>&1
! fm_pr_poll_artifacts_valid "$HOME_LAB/state" valid "$ROOT/bin/fm-pr-poll.sh"
printf 'Detect-only bootstrap leaves historical watch unchanged.\n'
FM_HOME="$HOME_LAB" FM_ROOT_OVERRIDE="$ROOT" FM_SESSION_START_TIMEOUT=30 "$ROOT/bin/fm-session-start.sh" > "$EVIDENCE/rollout-repeat-session-start.log" 2>&1
fm_pr_poll_artifacts_valid "$HOME_LAB/state" valid "$ROOT/bin/fm-pr-poll.sh"
printf 'Real session-start restores authentication for the stale watch.\n'
