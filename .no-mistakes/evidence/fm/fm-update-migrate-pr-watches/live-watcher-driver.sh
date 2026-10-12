#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4R5YM2H6A7K9P7MAV034931
LAB=$(mktemp -d "$ROOT/.test-phase-tmp/watcher.XXXXXX")
api_pid=
cleanup() { [ -z "$api_pid" ] || { kill "$api_pid" 2>/dev/null || true; wait "$api_pid" 2>/dev/null || true; }; rm -rf "$LAB"; }
trap cleanup EXIT
"$ROOT/bin/fm-lab-home.sh" create "$LAB/home" >/dev/null
export TMPDIR="$LAB" GH_CONFIG_DIR="$LAB/gh" GH_TOKEN=disposable-fixture-token
unset FM_GATE_REFUSE_BYPASS FM_TEST_SEAM FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
export TMUX="$LAB/private-socket,0,0"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$LAB/key.pem" -out "$LAB/cert.pem" -days 1 -subj /CN=api.github.com -addext subjectAltName=DNS:api.github.com >/dev/null 2>&1
uv run --no-project "$EVIDENCE/forge-api-fixture.py" "$LAB/cert.pem" "$LAB/key.pem" "$LAB/port" > "$EVIDENCE/forge-api.log" 2>&1 &
api_pid=$!
for unused in {1..100}; do [ ! -f "$LAB/port" ] || break; sleep .1; done
[ -f "$LAB/port" ]
export HTTPS_PROXY="http://127.0.0.1:$(cat "$LAB/port")"
export HTTP_PROXY="$HTTPS_PROXY" SSL_CERT_FILE="$LAB/cert.pem" NO_PROXY=
export ALL_PROXY="$HTTPS_PROXY"
printf 'Real gh reading the disposable API: '
gh pr view https://github.com/example/disposable/pull/1 --json state -q .state
. "$ROOT/bin/fm-pr-lib.sh"
state="$LAB/home/state"
printf 'pr=https://github.com/example/disposable/pull/1\n' > "$state/task-a.meta"
chmod 600 "$state/task-a.meta"
git show '20dcbf91520b1816663b81873ad67d0b93b3e4d6^:bin/fm-pr-poll.sh' > "$LAB/historical-poll.sh"
fm_pr_poll_prepare "$state" task-a github https://github.com/example/disposable/pull/1 github.com example/disposable 1 "$LAB/historical-poll.sh"
fm_pr_poll_publish_prepared
# The old registered generation is valid, but the watcher rejects stale program bytes.
rc=0
FM_HOME="$LAB/home" FM_ROOT_OVERRIDE="$ROOT" FM_POLL=.1 FM_CHECK_INTERVAL=0 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 timeout 12 "$ROOT/bin/fm-watch.sh" > "$EVIDENCE/watcher-before.log" 2>&1 || rc=$?
[ "$rc" = 0 ] || [ "$rc" = 124 ]
grep -F 'rejected unauthenticated state checks:' "$EVIDENCE/watcher-before.log"
FM_HOME="$LAB/home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-pr-check.sh" migrate-all
rc=0
FM_HOME="$LAB/home" FM_ROOT_OVERRIDE="$ROOT" FM_POLL=.1 FM_CHECK_INTERVAL=0 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 timeout 20 "$ROOT/bin/fm-watch.sh" > "$EVIDENCE/watcher-after.log" 2>&1 || rc=$?
[ "$rc" = 0 ] || [ "$rc" = 124 ]
if grep -qF 'check: rearm-resurface' "$EVIDENCE/watcher-after.log"; then
  FM_HOME="$LAB/home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-wake-drain.sh" > "$EVIDENCE/watcher-drain.log" 2> "$LAB/ack"
  sequence=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9][0-9]*\) --recovery-generation .*$/\1/p' "$LAB/ack")
  generation=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-][A-Za-z0-9._-]*\)$/\1/p' "$LAB/ack")
  FM_HOME="$LAB/home" FM_ROOT_OVERRIDE="$ROOT" "$ROOT/bin/fm-wake-drain.sh" --ack-through "$sequence" --recovery-generation "$generation"
  FM_HOME="$LAB/home" FM_ROOT_OVERRIDE="$ROOT" FM_POLL=.1 FM_CHECK_INTERVAL=0 FM_HEARTBEAT=999999 FM_SIGNAL_GRACE=0 timeout 20 "$ROOT/bin/fm-watch.sh" >> "$EVIDENCE/watcher-after.log" 2>&1 || rc=$?
fi
cat "$EVIDENCE/watcher-after.log"
grep -E 'check: .*task-a.check.sh: merged' "$EVIDENCE/watcher-after.log"
! grep -F 'rejected unauthenticated state checks:' "$EVIDENCE/watcher-after.log"
printf 'Real watcher accepted the migrated program and detected the merged PR through real gh.\n'
