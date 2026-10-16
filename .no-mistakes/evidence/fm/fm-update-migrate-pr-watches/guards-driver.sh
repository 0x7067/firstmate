#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
WORLD=$(mktemp -d "$ROOT/.phase-tmp/guards.XXXXXX")
trap 'rm -rf "$WORLD"' EXIT
unset FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
. "$ROOT/bin/fm-pr-lib.sh"
cp bin/fm-pr-poll.sh "$WORLD/historical"
printf '\n# Historical bytes\n' >> "$WORLD/historical"
for mutation in swapped-check swapped-sidecar altered-check altered-sidecar changed-pr partial-device retirement; do
  home="$WORLD/$mutation"
  bash bin/fm-lab-home.sh create "$home" >/dev/null
  state="$home/state"
  printf 'pr=https://github.com/o/r/pull/1\n' > "$state/task.meta"
  chmod 600 "$state/task.meta"
  fm_pr_poll_prepare "$state" task github https://github.com/o/r/pull/1 github.com o/r 1 "$WORLD/historical"
  fm_pr_poll_publish_prepared
  device=$(fm_pr_file_device "$state")
  awk -v device="$device" -v shifted="$((device+1))" -v mutation="$mutation" 'NR == 10 || (NR == 11 && mutation != "partial-device") { sub("^" device ":", shifted ":") } {print}' "$state/task.pr-poll-registration" > "$WORLD/shifted"
  chmod 600 "$WORLD/shifted"
  mv "$WORLD/shifted" "$state/task.pr-poll-registration"
  case "$mutation" in
    swapped-check|swapped-sidecar)
      file="$state/task.check.sh"
      [ "$mutation" != swapped-sidecar ] || file="$state/task.pr-poll"
      cp -p "$file" "$WORLD/replacement"
      mv "$WORLD/replacement" "$file"
      ;;
    altered-check) printf '\n' >> "$state/task.check.sh" ;;
    altered-sidecar) printf 'github\nhttps://github.com/o/r/pull/2\ngithub.com\no/r\n2\n' > "$state/task.pr-poll" ;;
    changed-pr) printf 'pr=https://github.com/o/r/pull/2\n' > "$state/task.meta" ;;
    retirement) touch "$state/task.pr-poll-retirement"; chmod 600 "$state/task.pr-poll-retirement" ;;
  esac
  snapshot() {
    for file in "$state/task."*; do
      stat -c '%n:%d:%i:%a:%h' "$file"
      sha256sum "$file"
    done
  }
  before=$(snapshot)
  echo '$ FM_HOME=<'"$mutation"'> bin/fm-pr-check.sh migrate-all'
  rc=0
  FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" bash bin/fm-pr-check.sh migrate-all || rc=$?
  [ "$rc" = 1 ]
  [ "$before" = "$(snapshot)" ]
  echo "$mutation: exit=$rc; registration, program, sidecar and metadata preserved byte-for-byte with the same identities and permissions"
done
