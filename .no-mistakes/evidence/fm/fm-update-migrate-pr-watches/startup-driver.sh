#!/usr/bin/env bash
set -eu
ROOT=$PWD
W=$(mktemp -d "$PWD/.phase-tmp/startup.XXXXXX")
trap 'rm -rf "$W"' EXIT
export TMPDIR="$W"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
mkdir "$W/home"
"$ROOT/bin/fm-lab-home.sh" create "$W/home" >/dev/null
cp -R "$ROOT/bin" "$W/home/"
printf 'lab\n' > "$W/home/AGENTS.md"
printf 'manual\n' > "$W/home/config/backlog-backend"
cp "$ROOT/bin/fm-pr-poll.sh" "$W/historical"
printf '\n' >> "$W/historical"
. "$ROOT/bin/fm-pr-lib.sh"
for id in valid invalid; do
  printf 'pr=https://github.com/lab/repo/pull/1\n' > "$W/home/state/$id.meta"
  chmod 600 "$W/home/state/$id.meta"
  fm_pr_poll_prepare "$W/home/state" "$id" github https://github.com/lab/repo/pull/1 github.com lab/repo 1 "$W/historical"
  fm_pr_poll_publish_prepared
done
printf 'pr=https://github.com/lab/repo/pull/2\n' > "$W/home/state/invalid.meta"
cp "$W/home/state/invalid.check.sh" "$W/invalid-before"
cp "$W/home/state/valid.meta" "$W/meta-before"
printf 'DETECT-ONLY STARTUP\n'
FM_HOME="$W/home" FM_BOOTSTRAP_DETECT_ONLY=1 FM_BOOTSTRAP_NETWORK=skip "$W/home/bin/fm-bootstrap.sh"
! fm_pr_poll_artifacts_valid "$W/home/state" valid "$ROOT/bin/fm-pr-poll.sh"
printf 'Detect-only bootstrap leaves authenticated historical watch stale.\n'
printf '\nNORMAL SESSION START\n'
FM_HOME="$W/home" "$W/home/bin/fm-session-start.sh" > "$W/session.txt" 2>&1
cat "$W/session.txt"
fm_pr_poll_artifacts_valid "$W/home/state" valid "$ROOT/bin/fm-pr-poll.sh"
! fm_pr_poll_artifacts_valid "$W/home/state" invalid "$ROOT/bin/fm-pr-poll.sh"
cmp "$W/home/state/valid.meta" "$W/meta-before"
cmp "$W/home/state/invalid.check.sh" "$W/invalid-before"
printf '\nNormal startup restores valid watch; refuses changed PR identity; preserves metadata and invalid bytes.\n'
