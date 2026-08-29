#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:?usage: quota-cli-e2e.sh <firstmate-root>}
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-quota-e2e.XXXXXX")
FAKEBIN="$LAB/fakebin"
HOME_DIR="$LAB/home"
STATE_DIR="$HOME_DIR/state"
CLAIM_ROOT="$LAB/claims"
COUNT_FILE="$LAB/quota-calls"
SNAPSHOT="$LAB/captured.json"

cleanup() {
  FM_HOME="$HOME_DIR" FM_STATE_OVERRIDE="$STATE_DIR" FM_PROCEVENT_CLAIM_ROOT="$CLAIM_ROOT" \
    "$ROOT/bin/fm-procevent-quota.sh" retire --provider codex >/dev/null 2>&1 || true
  rm -rf "$LAB"
}
trap cleanup EXIT

mkdir -p "$FAKEBIN" "$STATE_DIR" "$CLAIM_ROOT"

cat > "$FAKEBIN/quota-axi" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--version" ]; then
  printf 'quota-axi 0.1.32\n'
  exit 0
fi
count=0
[ ! -f "$QUOTA_E2E_COUNT" ] || read -r count < "$QUOTA_E2E_COUNT"
count=$((count + 1))
printf '%s\n' "$count" > "$QUOTA_E2E_COUNT"
if [ "$count" -eq 1 ]; then
  remaining=24
  runway=through_reset
else
  remaining=0
  runway=exhausted_now
fi
printf '{"schemaVersion":5,"providers":[{"provider":"codex","quotaSemantics":{"status":"known","effectiveAvailability":[{"scope":"all_models","status":"known","effectivePercentRemaining":%s,"runway":{"status":"%s"}}]}}]}\n' "$remaining" "$runway"
SH
chmod +x "$FAKEBIN/quota-axi"

cat > "$SNAPSHOT" <<'JSON'
{"schemaVersion":5,"providers":[{"provider":"claude","quotaSemantics":{"status":"known","effectiveAvailability":[{"scope":"all_models","status":"known","effectivePercentRemaining":0,"runway":{"status":"exhausted_now"}}]}},{"provider":"codex","quotaSemantics":{"status":"known","effectiveAvailability":[{"scope":"all_models","status":"known","effectivePercentRemaining":24,"runway":{"status":"through_reset"}}]}}]}
JSON

printf 'CHOOSER\n'
printf '$ fm-quota-choose.sh --snapshot captured.json --candidate claude:default --candidate codex:default\n'
PATH="$FAKEBIN:$PATH" "$ROOT/bin/fm-quota-choose.sh" --snapshot "$SNAPSHOT" \
  --candidate claude:default --candidate codex:default
if [ -f "$COUNT_FILE" ]; then
  printf 'unexpected quota-axi calls during chooser: '
  cat "$COUNT_FILE"
  exit 1
fi
printf 'quota-axi calls during chooser: 0\n'

printf '\nARM AND WAKE\n'
export FM_HOME="$HOME_DIR"
export FM_STATE_OVERRIDE="$STATE_DIR"
export FM_PROCEVENT_CLAIM_ROOT="$CLAIM_ROOT"
export QUOTA_E2E_COUNT="$COUNT_FILE"
export PATH="$FAKEBIN:$PATH"

printf '$ fm-procevent-quota.sh arm --interval 0.05 --threshold 10 --provider codex\n'
"$ROOT/bin/fm-procevent-quota.sh" arm --interval 0.05 --threshold 10 --provider codex
printf '$ fm-procevent.sh list\n'
"$ROOT/bin/fm-procevent.sh" list
printf '$ fm-procevent.sh reconcile\n'
"$ROOT/bin/fm-procevent.sh" reconcile

result=
for _ in $(seq 1 100); do
  result=$(find "$STATE_DIR/procevent-inbox" -type f -name 'quota-codex.*.result' -print -quit 2>/dev/null || true)
  [ -z "$result" ] || break
  sleep 0.05
done
[ -n "$result" ] || { printf 'no durable quota result appeared\n' >&2; exit 1; }

for _ in $(seq 1 100); do
  [ -s "$STATE_DIR/.wake-queue" ] && break
  sleep 0.05
done
[ -s "$STATE_DIR/.wake-queue" ] || { printf 'no durable quota wake appeared\n' >&2; exit 1; }

printf '$ cat durable-result\n'
sed -n '1,80p' "$result"
printf '$ fm-procevent-quota.sh classify durable-result\n'
"$ROOT/bin/fm-procevent-quota.sh" classify "$result"
printf '$ cat state/.wake-queue\n'
sed -n '1,80p' "$STATE_DIR/.wake-queue"

sequence=${result%.result}
sequence=${sequence##*.}
printf '$ fm-procevent.sh handled quota-codex %s\n' "$sequence"
"$ROOT/bin/fm-procevent.sh" handled quota-codex "$sequence"
printf 'quota-axi poll calls: '
cat "$COUNT_FILE"
