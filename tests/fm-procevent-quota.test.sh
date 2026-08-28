#!/usr/bin/env bash
# Behavioral tests for bin/fm-procevent-quota.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BIN="$FM_ROOT/bin"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-procevent-quota.XXXXXX")
FAKEBIN="$LAB/fakebin"
COUNT="$LAB/count"

cleanup() { rm -rf "$LAB"; }
trap cleanup EXIT
mkdir -p "$FAKEBIN"

cat > "$FAKEBIN/quota-axi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  printf 'quota-axi 0.1.29\n'
  exit 0
fi
count=0
[ ! -f "$QUOTA_AXI_COUNT" ] || read -r count < "$QUOTA_AXI_COUNT"
count=$((count + 1))
printf '%s\n' "$count" > "$QUOTA_AXI_COUNT"
if [ "$count" -eq 1 ]; then
  model_remaining=20
  runway=through_reset
else
  model_remaining=0
  runway=exhausted_now
fi
printf '{"schemaVersion":5,"providers":[{"provider":"codex","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","status":"known","effectivePercentRemaining":20,"runway":{"status":"through_reset"}},{"scope":"model:codex_bengalfox","status":"known","effectivePercentRemaining":%s,"runway":{"status":"%s"}}]}},{"provider":"claude","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","status":"known","effectivePercentRemaining":50,"runway":{"status":"through_reset"}}]}}]}\n' "$model_remaining" "$runway"
SH
chmod +x "$FAKEBIN/quota-axi"

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok - %s\n' "$1"; }

out=$(QUOTA_AXI_COUNT="$COUNT" PATH="$FAKEBIN:$PATH" "$BIN/fm-procevent-quota.sh" poll --interval 0.01 --threshold 10 --provider codex --timeout 1)
printf '%s\n' "$out" | grep -qx 'status: exhausted' || fail "provider watch did not report exhaustion"
printf '%s\n' "$out" | grep -qx 'condition_polls: 2' || fail "provider watch did not wait through the healthy poll"
ok "provider watch blocks until a model scope is exhausted"

rm -f "$COUNT"
out=$(QUOTA_AXI_COUNT="$COUNT" PATH="$FAKEBIN:$PATH" "$BIN/fm-procevent-quota.sh" poll --interval 0.01 --threshold 10 --provider '' --timeout 1)
printf '%s\n' "$out" | grep -qx 'status: exhausted' || fail "aggregate watch did not report exhaustion"
printf '%s\n' "$out" | grep -qx 'condition_polls: 2' || fail "aggregate watch did not evaluate all providers"
ok "aggregate watch blocks until any scope is exhausted"

printf '# all fm-procevent-quota tests passed\n'
