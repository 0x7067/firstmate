#!/usr/bin/env bash
# Unit tests for bin/fm-quota-choose.sh.
# Drives the public argv interface with a mocked quota-axi JSON source.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BIN="$FM_ROOT/bin"

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-quota-choose.XXXXXX")
FIXTURE="$LAB/quota.json"
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
            "effectivePercentRemaining": 50,
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
out=$(call_choose --json-source "$FIXTURE" --candidate kim:default --candidate codex:model:codex_bengalfox --candidate claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "first positive: expected 'claude claude-3-5-sonnet', got '$out'"
ok "first positive candidate wins"

# 2. Exhausted provider is skipped.
out=$(call_choose --json-source "$FIXTURE" --candidate kim:default --candidate claude:claude-3-5-sonnet)
[ "$out" = "claude claude-3-5-sonnet" ] || fail "exhausted skip: expected 'claude claude-3-5-sonnet', got '$out'"
ok "exhausted provider is skipped"

# 3. No candidates have positive quota.
if out=$(call_choose --json-source "$FIXTURE" --candidate kim:default 2>/dev/null); then
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

printf '# all fm-quota-choose tests passed\n'
