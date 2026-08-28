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
DUPLICATE="$LAB/duplicate.json"
OUT_OF_RANGE="$LAB/out-of-range.json"
INVALID_RUNWAY="$LAB/invalid-runway.json"
INVALID_AVAILABILITY="$LAB/invalid-availability.json"
TOON="$LAB/quota.toon"
FAKEBIN="$LAB/fakebin"
CALLS="$LAB/calls"

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
      "provider": "pi",
      "windows": [],
      "quotaSemantics": {
        "status": "known",
        "effectiveAvailability": [
          {
            "scope": "all_models",
            "status": "known",
            "effectivePercentRemaining": 50,
            "runway": { "status": "through_reset" }
          }
        ]
      }
    },
    {
      "provider": "xai",
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
          },
          {
            "scope": "model:fable",
            "status": "known",
            "effectivePercentRemaining": 0,
            "runway": { "status": "exhausted_now" }
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
  echo "quota-axi 0.1.29"
  exit 0
fi
printf 'called\n' >> "${QUOTA_AXI_CALLS:?}"
cat "${QUOTA_AXI_FIXTURE:?}"
SH
chmod +x "$FAKEBIN/quota-axi"

QUOTA_AXI_CALLS="$CALLS" QUOTA_AXI_FIXTURE="$FIXTURE" "$FAKEBIN/quota-axi" --json > "$LAB/captured.json"

call_choose() {
  "$BIN/fm-quota-choose.sh" "$@"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

ok() {
  printf 'ok - %s\n' "$1"
}

# 1. First candidate with positive effective quota.
out=$(call_choose --snapshot "$LAB/captured.json" --candidate kimi:kimi:default --candidate codex:codex:model:codex_bengalfox --candidate claude:claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "first positive: expected 'claude claude-3-5-sonnet', got '$out'"
ok "first positive candidate wins"

# 2. Exhausted provider is skipped.
out=$(call_choose --snapshot "$LAB/captured.json" --candidate kimi:kimi:default --candidate claude:claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "exhausted skip: expected 'claude claude-3-5-sonnet', got '$out'"
ok "exhausted provider is skipped"

# 3. No candidates have positive quota.
if out=$(call_choose --snapshot "$LAB/captured.json" --candidate kimi:kimi:default 2>/dev/null); then
  fail "no positive: expected exit 1, got exit 0 with '$out'"
fi
[ "$out" = "none" ] || fail "no positive: expected 'none', got '$out'"
ok "no positive candidate returns none and exit 1"

# 4. Positional arguments work.
out=$(call_choose --snapshot "$LAB/captured.json" claude:claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "positional: expected 'claude claude-3-5-sonnet', got '$out'"
ok "positional candidates work"

# 5. A model-specific exhausted scope bounds a healthy all-models scope.
if out=$(call_choose --snapshot "$LAB/captured.json" --candidate codex:codex:model:codex_bengalfox 2>/dev/null); then
  fail "specific scope: expected exit 1, got exit 0 with '$out'"
fi
[ "$out" = "none" ] || fail "specific scope: expected 'none', got '$out'"
ok "specific model scope bounds generic quota"

out=$(call_choose --snapshot "$LAB/captured.json" --candidate codex:codex:default)
[ "$out" = "codex default" ] || fail "default scope: expected provider-wide quota, got '$out'"
ok "default model uses provider-wide quota"

out=$(call_choose --snapshot "$LAB/captured.json" --candidate claude:claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "fractional quota: expected positive candidate, got '$out'"
ok "fractional positive quota is eligible"

if err=$(call_choose --snapshot "$LAB/captured.json" --candidate bogus:claude:model --candidate claude:claude:claude-3-5-sonnet 2>&1); then
  fail "unknown harness unexpectedly selected a later candidate"
fi
[ "$err" = "error: unknown harness: bogus" ] || fail "unknown harness returned: $err"
ok "unknown harness fails closed"

printf '{"schemaVersion":5,"providers":{"provider":"claude","quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","status":"known","effectivePercentRemaining":50,"runway":{"status":"through_reset"}}]}}}\n' > "$MALFORMED"
if err=$(call_choose --snapshot "$MALFORMED" --candidate claude:claude:default 2>&1); then
  fail "malformed provider collection unexpectedly dispatched"
fi
[ "$err" = "error: invalid quota-axi provider data" ] || fail "malformed provider data returned: $err"
ok "malformed provider data fails closed"

out=$(call_choose --candidate claude:claude:default < "$LAB/captured.json")
[ "$out" = "claude default" ] || fail "stdin snapshot returned '$out'"
ok "stdin snapshot is accepted"

if err=$(call_choose --snapshot "$LAB/captured.json" --candidate claude:claude: 2>&1); then
  fail "empty model candidate unexpectedly dispatched"
fi
[ "$err" = "error: invalid candidate: claude:claude:" ] || fail "empty model candidate returned: $err"
ok "empty model candidate fails closed"

if err=$(call_choose --snapshot "$LAB/captured.json" --candidate claude:default 2>&1); then
  fail "candidate without separator unexpectedly dispatched"
fi
[ "$err" = "error: invalid candidate: claude:default" ] || fail "candidate without provider returned: $err"
ok "candidate requires harness-provider-model fields"

cat > "$TOON" <<'TOON'
bin: quota-axi
generatedAt: "2030-01-01T00:00:00Z"
quota[2]{provider,scope,effectivePercentRemaining,spendPriority,runway,confidence,limitedBy,resetsAt}:
  codex,all_models,20,-1,through_reset,high,weekly,2030-01-02T00:00:00Z
  claude,all_models,0.5,-1,through_reset,high,weekly,2030-01-02T00:00:00Z
exhaustion[0]:
attention[0]:
TOON
out=$(call_choose --snapshot "$TOON" --candidate claude:claude:default)
[ "$out" = "claude default" ] || fail "default TOON snapshot returned '$out'"
ok "default TOON snapshot is accepted"

[ "$(wc -l < "$CALLS" | tr -d '[:space:]')" = 1 ] || fail "helper took an additional quota snapshot"
ok "helper reuses the captured quota snapshot"

if out=$(call_choose --snapshot "$LAB/captured.json" --candidate pi:xai:grok-4 2>/dev/null); then
  fail "multi-provider harness used Pi quota instead of explicit xAI quota"
fi
[ "$out" = "none" ] || fail "explicit exhausted provider returned '$out'"
ok "explicit provider controls quota matching"

jq '.providers += [.providers[] | select(.provider == "claude")]' "$LAB/captured.json" > "$DUPLICATE"
if err=$(call_choose --snapshot "$DUPLICATE" --candidate claude:claude:default 2>&1); then
  fail "duplicate provider snapshot unexpectedly dispatched"
fi
[ "$err" = "error: invalid quota-axi provider data" ] || fail "duplicate provider returned: $err"
ok "duplicate providers fail closed"

jq '(.providers[] | select(.provider == "claude").quotaSemantics.effectiveAvailability[0].effectivePercentRemaining) = 150' "$LAB/captured.json" > "$OUT_OF_RANGE"
if err=$(call_choose --snapshot "$OUT_OF_RANGE" --candidate claude:claude:default 2>&1); then
  fail "out-of-range quota unexpectedly dispatched"
fi
[ "$err" = "error: invalid quota-axi provider data" ] || fail "out-of-range quota returned: $err"
ok "out-of-range quota fails closed"

jq '(.providers[] | select(.provider == "claude").quotaSemantics.effectiveAvailability[0].runway.status) = "invalid"' "$LAB/captured.json" > "$INVALID_RUNWAY"
if err=$(call_choose --snapshot "$INVALID_RUNWAY" --candidate claude:claude:default 2>&1); then
  fail "invalid runway status unexpectedly dispatched"
fi
[ "$err" = "error: invalid quota-axi provider data" ] || fail "invalid runway status returned: $err"
ok "invalid runway status fails closed"

if out=$(call_choose --snapshot "$LAB/captured.json" --candidate claude:claude:fable 2>/dev/null); then
  fail "exact named model exhaustion unexpectedly dispatched"
fi
[ "$out" = "none" ] || fail "exact named model returned '$out'"
out=$(call_choose --snapshot "$LAB/captured.json" --candidate claude:claude:fable-2)
[ "$out" = "claude fable-2" ] || fail "named model scope overmatched fable-2: $out"
out=$(call_choose --snapshot "$LAB/captured.json" --candidate claude:claude:default)
[ "$out" = "claude default" ] || fail "named model scope overmatched default: $out"
ok "named model quota matches exact identity only"

jq '(.providers[] | select(.provider == "claude").quotaSemantics.effectiveAvailability[1].status) = "typo"' "$LAB/captured.json" > "$INVALID_AVAILABILITY"
if err=$(call_choose --snapshot "$INVALID_AVAILABILITY" --candidate claude:claude:default 2>&1); then
  fail "invalid availability status unexpectedly dispatched"
fi
[ "$err" = "error: invalid quota-axi provider data" ] || fail "invalid availability status returned: $err"
ok "invalid availability status fails closed"

printf '# all fm-quota-choose tests passed\n'
