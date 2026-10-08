#!/usr/bin/env bash
root=/home/denguinho/.no-mistakes/worktrees/159e9a668321/01M4CE93TQQAHQD97QWA2QR4XZ
out=$(mktemp "$root/.test-live/tmp/call.XXXXXX")
"$root/bin/fm-herdr-lab.sh" "$@" > "$out"
rc=$?
{
  printf '\nCOMMAND'; printf ' %q' "$@"; printf '\n'
  cat "$out"
  printf '\nexit=%s\n' "$rc"
} >> /home/denguinho/.no-mistakes/evidence/01M4CE93TQQAHQD97QWA2QR4XZ/live-transcript.log
cat "$out"
rm -f "$out"
exit "$rc"
