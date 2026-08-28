#!/usr/bin/env bash
# Choose the first candidate with positive effective quota from a ranked list.
#
# Usage:
#   fm-quota-choose.sh [--json-source <path>] [--candidate <harness:model>]...
#
# Reads `quota-axi --json` (or the provided JSON snapshot) and, for each
# --candidate in order, looks up the provider family for <harness>, then the
# best matching quota scope for <model>. The first candidate whose effective
# percent remaining is > 0 and whose runway.status is not `exhausted_now` is
# printed as "<harness> <model>" and the script exits 0. If no candidate has
# positive effective quota, prints "none" and exits 1.
#
# Candidates are accepted as `--candidate <harness:model>` or as positional
# colon-separated arguments, with earlier candidates preferred.
# This script is deterministic and safe: it performs no side effects and exits
# nonzero when the environment would lead to an unsafe dispatch.
#
# The helper is the canonical worker-side selection used after the agent has
# already run `quota-axi` for its model selection. It never replaces the agent's
# reasoning-class or runway-feasibility gates; it only answers the narrow
# question "which of these candidates has positive effective quota right now".
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bin/fm-quota-axi-lib.sh
. "$SCRIPT_DIR/fm-quota-axi-lib.sh"

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
usage() { sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

CANDIDATES=()
JSON_SOURCE=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json-source)
      [ -n "${2-}" ] || die "--json-source needs a path"
      JSON_SOURCE=$2
      shift 2
      ;;
    --candidate)
      [ -n "${2-}" ] || die "--candidate needs a value"
      CANDIDATES+=("$2")
      shift 2
      ;;
    -h|--help|help) usage ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) CANDIDATES+=("$1") ; shift ;;
  esac
done

# Positional args after an explicit -- are also candidates.
while [ "$#" -gt 0 ]; do
  CANDIDATES+=("$1"); shift
done

[ "${#CANDIDATES[@]}" -gt 0 ] || die "no candidates supplied"

for c in "${CANDIDATES[@]}"; do
  case "$c" in
    ''|*[!A-Za-z0-9._/:-]*) die "invalid candidate: $c" ;;
  esac
done

fm_quota_axi_compatible 5 >/dev/null 2>&1 || die "quota-axi is missing or below the compatibility floor"

if [ -n "$JSON_SOURCE" ]; then
  [ -f "$JSON_SOURCE" ] && [ ! -L "$JSON_SOURCE" ] || die "json source is not a regular file: $JSON_SOURCE"
  QUOTA_JSON=$(cat -- "$JSON_SOURCE") || die "cannot read json source: $JSON_SOURCE"
else
  QUOTA_JSON=$(quota-axi --json 2>/dev/null) || die "quota-axi --json failed"
fi
[ -n "$QUOTA_JSON" ] || die "empty quota-axi json output"

# Verify the JSON is the schema version we understand.
schema=$(printf '%s\n' "$QUOTA_JSON" | jq -r '.schemaVersion // empty' 2>/dev/null) || schema=
case "$schema" in
  5) ;;
  '') die "quota-axi json missing schemaVersion" ;;
  *) die "unsupported quota-axi schema version: $schema" ;;
esac

# provider_for_harness <harness>
# Map a firstmate harness name to the quota-axi provider family it consumes.
provider_for_harness() {
  case "$1" in
    claude)     printf 'claude\n' ;;
    codex)      printf 'codex\n' ;;
    opencode)   printf 'codex\n' ;;
    pi|pi-signed) printf 'pi\n' ;;
    prime-agent) printf 'pi\n' ;;
    grok)       printf 'grok\n' ;;
    kimi)       printf 'kimi\n' ;;
    cursor)     printf 'cursor\n' ;;
    agy)        printf 'agy\n' ;;
    copilot)    printf 'copilot\n' ;;
    *)          return 1 ;;
  esac
}

# scope_matches_model <scope> <model>
# Return 0 when <scope> (a quota-axi scope string like "all_models" or
# "model:codex_bengalfox") covers the candidate's model token.
# The model token may be "default" (no explicit model), a model id that maps to
# a provider model prefix, or empty.
scope_matches_model() {
  local scope=$1 model=${2:-default}
  case "$scope" in
    all_models|all_products)
      return 0
      ;;
    model:*)
      local prefix=${scope#model:}
      case "$model" in
        default|''|"$prefix"*)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    tools)
      case "$model" in *mcp*|*tool*) return 0 ;; *) return 1 ;; esac
      ;;
    *)
      return 1
      ;;
  esac
}

# effective_for_provider_model <provider> <model>
# Print a JSON object with effectivePercentRemaining and runway.status for the
# provider/model tuple, preferring the most specific known scope.
effective_for_provider_model() {
  local provider=$1 model=${2:-default}
  printf '%s\n' "$QUOTA_JSON" | jq -c --arg provider "$provider" --arg model "$model" '
    .providers[]? | select(.provider == $provider) |
    (.quotaSemantics.effectiveAvailability // []) |
    map(select(.status == "known")) |
    map(select(.scope as $s | $model == "" or $model == "default" or
      ($s == "all_models" or $s == "all_products" or
       ($s | startswith("model:")) as $is_model |
       ($is_model and ($s | ltrimstr("model:") | startswith($model)))
      )
    )) |
    if length == 0 then null
    else
      sort_by(
        if .scope == "all_models" or .scope == "all_products" then 0
        elif .scope | startswith("model:") then 2
        else 1 end,
        .effectivePercentRemaining
      )[0]
    end
  ' 2>/dev/null
}

chosen="none"
for c in "${CANDIDATES[@]}"; do
  harness=${c%%:*}
  model=${c#*:}
  [ "$model" = "$c" ] && model="default"
  provider=$(provider_for_harness "$harness") || { printf 'error: unknown harness: %s\n' "$harness" >&2; continue; }
  effective=$(effective_for_provider_model "$provider" "$model")
  if [ -z "$effective" ] || [ "$effective" = "null" ]; then
    continue
  fi
  remaining=$(printf '%s\n' "$effective" | jq -r '.effectivePercentRemaining // empty')
  runway=$(printf '%s\n' "$effective" | jq -r '.runway.status // empty')
  case "$remaining" in
    ''|*[!0-9]*|null) continue ;;
  esac
  if [ "$remaining" -gt 0 ] && [ "$runway" != "exhausted_now" ]; then
    chosen="$harness $model"
    break
  fi
done

printf '%s\n' "$chosen"
[ "$chosen" != "none" ]
