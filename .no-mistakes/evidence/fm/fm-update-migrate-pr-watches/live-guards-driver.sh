#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
LAB=$(mktemp -d "$ROOT/.test-phase-tmp/guards.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
. "$ROOT/bin/fm-pr-lib.sh"
git show '20dcbf91520b1816663b81873ad67d0b93b3e4d6^:bin/fm-pr-poll.sh' > "$LAB/old.sh"
for mutation in check-inode sidecar-inode check-bytes sidecar-bytes pr-identity hash-record private-mode hardlink partial-device retirement; do
  home="$LAB/$mutation"
  "$ROOT/bin/fm-lab-home.sh" create "$home" >/dev/null
  state="$home/state"
  printf 'pr=https://github.com/example/disposable/pull/1\n' > "$state/task-a.meta"
  chmod 600 "$state/task-a.meta"
  fm_pr_poll_prepare "$state" task-a github https://github.com/example/disposable/pull/1 github.com example/disposable 1 "$LAB/old.sh"
  fm_pr_poll_publish_prepared
  device=$(fm_pr_file_device "$state")
  awk -v d="$device" -v s="$((device+1))" 'NR==10 || NR==11 {sub("^"d":",s":")} {print}' "$state/task-a.pr-poll-registration" > "$state/shift"
  chmod 600 "$state/shift"; mv "$state/shift" "$state/task-a.pr-poll-registration"
  case "$mutation" in
    check-inode|sidecar-inode)
      artifact="$state/task-a.check.sh"
      [ "$mutation" != sidecar-inode ] || artifact="$state/task-a.pr-poll"
      cp "$artifact" "$state/swap"; chmod 600 "$state/swap"; mv "$state/swap" "$artifact" ;;
    check-bytes) printf '\n' >> "$state/task-a.check.sh" ;;
    sidecar-bytes) printf 'github\nhttps://github.com/example/disposable/pull/2\ngithub.com\nexample/disposable\n2\n' > "$state/task-a.pr-poll" ;;
    pr-identity) printf 'pr=https://github.com/example/disposable/pull/2\n' > "$state/task-a.meta" ;;
    hash-record) sed '9s/.*/0000000000000000000000000000000000000000000000000000000000000000/' "$state/task-a.pr-poll-registration" > "$state/swap"; chmod 600 "$state/swap"; mv "$state/swap" "$state/task-a.pr-poll-registration" ;;
    private-mode) chmod 640 "$state/task-a.check.sh" ;;
    hardlink) ln "$state/task-a.check.sh" "$home/linked" ;;
    partial-device) sed "11s/^$((device+1)):/$device:/" "$state/task-a.pr-poll-registration" > "$state/swap"; chmod 600 "$state/swap"; mv "$state/swap" "$state/task-a.pr-poll-registration" ;;
    retirement) touch "$state/task-a.pr-poll-retirement"; chmod 600 "$state/task-a.pr-poll-retirement" ;;
  esac
  before=$(sha256sum "$state"/task-a.*)
  rc=0
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-pr-check.sh" migrate-all || rc=$?
  [ "$rc" = 1 ]
  [ "$before" = "$(sha256sum "$state"/task-a.*)" ]
  printf '%s: refused without rewriting artifacts\n' "$mutation"
done
