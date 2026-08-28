#!/usr/bin/env bash
# Unit tests for bin/fm-quota-choose.sh.
# Drives the public argv interface with a mocked quota-axi JSON source.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BIN="$FM_ROOT/bin"

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-quota-choose.XXXXXX")
FIXTURE="$LAB/quota.json"
MALFORMED="$LAB/malformed.json"
FAKEBIN="$LAB/fakebin"

cleanup() {
  rm -rf "$LAB"
}
trap cleanup EXIT

mkdir -p "$FAKEBIN"

cat > "$FIXTURE" <<'JSON'
{
  "generatedAt": "2030-01-01T00:00:00Z",
  "schemaVersion": 5,
  "providers": [
    {
      "provider": "kimi",
      "windows": [],
      "quotaSemantics": {
        "status": "known",
        "effectiveAvailability": [
          {
            "scope": "all_models",
            "status": "known",
            "effectivePercentRemaining": 0,
            "runway": { "status": "exhausted_now" }
          }
        ]
      }
    },
    {
      "provider": "codex",
      "windows": [],
      "quotaSemantics": {
        "status": "known",
        "effectiveAvailability": [
          {
            "scope": "all_models",
            "status": "known",
            "effectivePercentRemaining": 20,
            "runway": { "status": "projected_exhaustion" }
          },
          {
            "scope": "model:codex_bengalfox",
            "status": "known",
            "effectivePercentRemaining": 0,
            "runway": { "status": "exhausted_now" }
          }
        ]
      }
    },
    {
      "provider": "claude",
      "windows": [],
      "quotaSemantics": {
        "status": "known",
        "effectiveAvailability": [
          {
            "scope": "all_models",
            "status": "known",
            "effectivePercentRemaining": 0.5,
            "runway": { "status": "through_reset" }
          }
        ]
      }
    }
  ]
}
JSON

cat > "$FAKEBIN/quota-axi" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  [ "${QUOTA_AXI_INCOMPATIBLE:-0}" != 1 ] || exit 1
  echo "quota-axi 0.1.29"
  exit 0
fi
cat "${QUOTA_AXI_FIXTURE:?}"
SH
chmod +x "$FAKEBIN/quota-axi"

call_choose() {
  QUOTA_AXI_FIXTURE="$FIXTURE" PATH="$FAKEBIN:$PATH" "$BIN/fm-quota-choose.sh" "$@"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

ok() {
  printf 'ok - %s\n' "$1"
}

# 1. First candidate with positive effective quota.
out=$(call_choose --json-source "$FIXTURE" --candidate kimi:default --candidate codex:model:codex_bengalfox --candidate claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "first positive: expected 'claude claude-3-5-sonnet', got '$out'"
ok "first positive candidate wins"

# 2. Exhausted provider is skipped.
out=$(call_choose --json-source "$FIXTURE" --candidate kimi:default --candidate claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "exhausted skip: expected 'claude claude-3-5-sonnet', got '$out'"
ok "exhausted provider is skipped"

# 3. No candidates have positive quota.
if out=$(call_choose --json-source "$FIXTURE" --candidate kimi:default 2>/dev/null); then
  fail "no positive: expected exit 1, got exit 0 with '$out'"
fi
[ "$out" = "none" ] || fail "no positive: expected 'none', got '$out'"
ok "no positive candidate returns none and exit 1"

# 4. Positional arguments work.
out=$(call_choose --json-source "$FIXTURE" claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "positional: expected 'claude claude-3-5-sonnet', got '$out'"
ok "positional candidates work"

# 5. A model-specific exhausted scope bounds a healthy all-models scope.
if out=$(call_choose --json-source "$FIXTURE" --candidate codex:model:codex_bengalfox 2>/dev/null); then
  fail "specific scope: expected exit 1, got exit 0 with '$out'"
fi
[ "$out" = "none" ] || fail "specific scope: expected 'none', got '$out'"
ok "specific model scope bounds generic quota"

if out=$(call_choose --json-source "$FIXTURE" --candidate codex:default 2>/dev/null); then
  fail "default scope: expected exit 1, got exit 0 with '$out'"
fi
[ "$out" = "none" ] || fail "default scope: expected 'none', got '$out'"
ok "default model observes provider model scopes"

out=$(call_choose --json-source "$FIXTURE" --candidate claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "fractional quota: expected positive candidate, got '$out'"
ok "fractional positive quota is eligible"

if err=$(call_choose --json-source "$FIXTURE" --candidate bogus:model --candidate claude:claude-3-5-sonnet 2>&1); then
  fail "unknown harness unexpectedly selected a later candidate"
fi
[ "$err" = "error: unknown harness: bogus" ] || fail "unknown harness returned: $err"
ok "unknown harness fails closed"

printf '{"schemaVersion":5,"providers":{"provider":"claude","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","status":"known","effectivePercentRemaining":50,"runway":{"status":"through_reset"}}]}}}\n' > "$MALFORMED"
if err=$(call_choose --json-source "$MALFORMED" --candidate claude:default 2>&1); then
  fail "malformed provider collection unexpectedly dispatched"
fi
[ "$err" = "error: invalid quota-axi provider data" ] || fail "malformed provider data returned: $err"
ok "malformed provider data fails closed"

out=$(QUOTA_AXI_INCOMPATIBLE=1 call_choose --json-source "$FIXTURE" --candidate claude:default)
[ "$out" = "claude default" ] || fail "json source required live quota-axi compatibility"
ok "json source does not require quota-axi"

if err=$(call_choose --json-source "$FIXTURE" --candidate claude: 2>&1); then
  fail "empty model candidate unexpectedly dispatched"
fi
[ "$err" = "error: invalid candidate: claude:" ] || fail "empty model candidate returned: $err"
ok "empty model candidate fails closed"

if err=$(call_choose --json-source "$FIXTURE" --candidate claude 2>&1); then
  fail "candidate without separator unexpectedly dispatched"
fi
[ "$err" = "error: invalid candidate: claude" ] || fail "candidate without separator returned: $err"
ok "candidate requires a harness-model separator"

printf '# all fm-quota-choose tests passed\n'
