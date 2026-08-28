#!/usr/bin/env bash
# Choose the first quota-eligible candidate from a ranked list.
#
# Usage:
#   fm-quota-choose.sh [--snapshot <path>] [--candidate <harness:model>]...
#
# Reads one already-captured quota-axi default TOON or JSON snapshot from the
# provided file, or from stdin when --snapshot is omitted. For each --candidate
# in order, it maps <harness> to its primary provider family, then matches the
# best quota scope for <model>. The first candidate with disclosed unknown
# quota, or with effective percent remaining > 0 and runway status other than
# `exhausted_now`, is printed as "<harness> <model>" and the script exits 0.
# If no candidate is quota-eligible, it prints "none" and exits 1.
#
# Candidates are accepted as `--candidate <harness:model>` or as positional
# colon-separated arguments, with earlier candidates preferred.
# This script is deterministic and safe: it performs no side effects and exits
# nonzero when the environment would lead to an unsafe dispatch.
#
# The helper is the canonical worker-side selection used after the agent has
# already run `quota-axi` for its model selection. It never replaces the agent's
# reasoning-class or runway-feasibility gates; it only answers which ordered
# candidate remains eligible under the captured quota evidence.
#
# Multi-provider limitation: this helper maps each harness to ONE primary
# provider family (see provider_for_harness below) and checks quota for that
# family only. Some harnesses can run models from several providers - for
# example, Pi and OpenCode may dispatch xAI, Anthropic, or other models - so a
# candidate whose established provider differs from the harness's primary family
# is checked against the wrong quota row. This is an accepted limitation of the
# optional helper. Authoritative multi-provider routing - including provider
# discovery from the harness catalog and quota matching by that explicit
# provider - is owned by AGENTS.md section 4 and the quota-array-dispatch skill,
# not by this helper. Use this helper only when the brief already fixed the
# candidate order and every candidate's provider is the harness's primary family.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=bin/fm-quota-axi-lib.sh
. "$SCRIPT_DIR/fm-quota-axi-lib.sh"
# shellcheck source=bin/fm-control-lib.sh
. "$SCRIPT_DIR/fm-control-lib.sh"

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

CANDIDATES=()
SNAPSHOT_SOURCE=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --snapshot)
      [ -n "${2-}" ] || die "--snapshot needs a path"
      SNAPSHOT_SOURCE=$2
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

# A candidate is <harness>:<model>. A bare harness with no colon means the
# default model. Reject empty harnesses and characters that cannot form a safe
# token. A colon-separated model is legal (e.g. model:codex_bengalfox).
for c in "${CANDIDATES[@]}"; do
  case "$c" in
    ''|:*|*[!A-Za-z0-9._/:-]*) die "invalid candidate: $c" ;;
  esac
done

if [ -n "$SNAPSHOT_SOURCE" ]; then
  [ -f "$SNAPSHOT_SOURCE" ] && [ ! -L "$SNAPSHOT_SOURCE" ] || die "snapshot is not a regular file: $SNAPSHOT_SOURCE"
  QUOTA_SNAPSHOT=$(cat -- "$SNAPSHOT_SOURCE") || die "cannot read snapshot: $SNAPSHOT_SOURCE"
else
  [ ! -t 0 ] || die "quota snapshot is required on stdin or with --snapshot"
  QUOTA_SNAPSHOT=$(cat) || die "cannot read quota snapshot from stdin"
fi
[ -n "$QUOTA_SNAPSHOT" ] || die "empty quota snapshot"

if printf '%s\n' "$QUOTA_SNAPSHOT" | jq -e 'type == "object"' >/dev/null 2>&1; then
  QUOTA_JSON=$QUOTA_SNAPSHOT
  schema=$(printf '%s\n' "$QUOTA_JSON" | jq -r '.schemaVersion // empty' 2>/dev/null) || schema=
  case "$schema" in
    5) ;;
    '') die "quota-axi json missing schemaVersion" ;;
    *) die "unsupported quota-axi schema version: $schema" ;;
  esac
else
  QUOTA_JSON=$(printf '%s\n' "$QUOTA_SNAPSHOT" | jq -Rse '
    if test("(?m)^quota\\[0\\]:[ \\t]*$") then
      {schemaVersion: 5, providers: []}
    else
      capture("(?m)^quota\\[(?<count>[0-9]+)\\]\\{provider,scope,effectivePercentRemaining,spendPriority,runway,confidence,limitedBy,resetsAt\\}:\\n(?<rows>(?:  [^\\n]*\\n?)*)") as $section |
      ($section.rows | split("\n") | map(select(length > 0) | sub("^  "; "") | split(","))) as $rows |
      if ($rows | length) != ($section.count | tonumber) or any($rows[]; length != 8) then error("invalid quota rows")
      else
        {
          schemaVersion: 5,
          providers: ($rows |
            map({
              provider: .[0],
              scope: .[1],
              effectivePercentRemaining: (.[2] | tonumber),
              runway: .[4]
            }) |
            group_by(.provider) |
            map({
              provider: .[0].provider,
              quotaSemantics: {
                status: "known",
                effectiveAvailability: map({
                  scope,
                  status: "known",
                  effectivePercentRemaining,
                  runway: {status: .runway}
                })
              }
            })
          )
        }
      end
    end
  ' 2>/dev/null) || die "invalid quota-axi snapshot"
fi

printf '%s\n' "$QUOTA_JSON" | fm_quota_json_valid || die "invalid quota-axi provider data"

# provider_for_harness <harness>
# Map a firstmate harness name to its primary quota-axi provider family.
# Multi-provider harnesses (Pi, OpenCode) map to their primary family only; see
# the header limitation note. Authoritative multi-provider routing is owned by
# AGENTS.md section 4 and the quota-array-dispatch skill, not this helper.
provider_for_harness() {
  case "$1" in
    claude)       printf 'claude\n' ;;
    codex)        printf 'codex\n' ;;
    opencode)     printf 'codex\n' ;;
    pi|pi-signed) printf 'pi\n' ;;
    grok)         printf 'grok\n' ;;
    kimi)         printf 'kimi\n' ;;
    cursor)       printf 'cursor\n' ;;
    muse)         printf 'meta\n' ;;
    *)            return 1 ;;
  esac
}

# effective_for_provider_model <provider> <model>
# Print a JSON object with effectivePercentRemaining and runway.status for the
# provider/model tuple, preferring the most specific known scope.
effective_for_provider_model() {
  local provider=$1 model=${2:-default}
  printf '%s\n' "$QUOTA_JSON" | jq -c --arg provider "$provider" --arg model "$model" '
    ($model | sub("^model:"; "")) as $model_token |
    ([.providers[]? | select(.provider == $provider)] | first) as $p |
    if ($p // null) == null then {status: "unknown"}
    else ($p.quotaSemantics.effectiveAvailability // []) |
    map(select(.scope as $scope |
      $scope == "all_models" or $scope == "all_products" or
      ($model_token != "" and $model_token != "default" and
       (($scope | startswith("model:")) or ($scope | startswith("product:"))) and
       ($model_token == ($scope | sub("^(model|product):"; ""))))
    )) as $applicable |
    ($applicable | map(select(.status == "known"))) as $known |
    if ($applicable | length) == 0 then {status: "unknown"}
    elif ($known | length) == 0 then {status: "unknown"}
    elif any($known[];
      .effectivePercentRemaining == 0 or
      (.runway.status // "") == "exhausted_now"
    ) then ($known | map(select(
      .effectivePercentRemaining == 0 or
      (.runway.status // "") == "exhausted_now"
    )) | first)
    else ($known | min_by(.effectivePercentRemaining))
    end
    end
  ' 2>/dev/null
}

chosen="none"
for c in "${CANDIDATES[@]}"; do
  harness=${c%%:*}
  model=${c#*:}
  [ "$model" = "$c" ] && model="default"
  [ -n "$model" ] || die "invalid candidate: $c"
  fm_control_harness_supported "$harness" || die "unknown harness: $harness"
  provider=$(provider_for_harness "$harness") || die "unknown harness: $harness"
  effective=$(effective_for_provider_model "$provider" "$model")
  if [ -z "$effective" ] || [ "$effective" = "null" ]; then
    continue
  fi
  if printf '%s\n' "$effective" | jq -e '
    if .status == "unknown" then true
    else
      .effectivePercentRemaining as $remaining |
      (($remaining | type) == "number") and
      ($remaining > 0) and
      ((.runway.status // "") != "exhausted_now")
    end
  ' >/dev/null 2>&1; then
    chosen="$harness $model"
    break
  fi
done

printf '%s\n' "$chosen"
[ "$chosen" != "none" ]
