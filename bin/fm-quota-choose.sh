#!/usr/bin/env bash
# Choose the first candidate with positive effective quota from a ranked list.
#
# Usage:
#   fm-quota-choose.sh [--snapshot <path>] [--candidate <harness:provider:model>]...
#
# Reads one already-captured quota-axi default TOON or JSON snapshot from the
# provided file, or from stdin when --snapshot is omitted. For each --candidate
# in order, it matches the explicit <provider>, then the best matching quota
# scope for <model>. The first candidate whose effective percent remaining
# is > 0 and whose runway status is not `exhausted_now` is printed as
# "<harness> <model>" and the script exits 0. If no candidate has positive
# effective quota, prints "none" and exits 1.
#
# Candidates are accepted as `--candidate <harness:provider:model>` or as
# positional colon-separated arguments, with earlier candidates preferred.
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
# shellcheck source=bin/fm-control-lib.sh
. "$SCRIPT_DIR/fm-control-lib.sh"

die() { printf 'error: %s\n' "$1" >&2; exit 2; }
usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }

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

for c in "${CANDIDATES[@]}"; do
  case "$c" in
    ''|:*|*:|*[!A-Za-z0-9._/:-]*) die "invalid candidate: $c" ;;
  esac
  candidate_rest=${c#*:}
  candidate_provider=${candidate_rest%%:*}
  candidate_model=${candidate_rest#*:}
  [ "$candidate_rest" != "$c" ] && [ "$candidate_model" != "$candidate_rest" ] \
    && [ -n "$candidate_provider" ] && [ -n "$candidate_model" ] \
    || die "invalid candidate: $c"
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
  ' 2>/dev/null) || die "invalid quota-axi snapshot"
fi

printf '%s\n' "$QUOTA_JSON" | fm_quota_json_valid || die "invalid quota-axi provider data"

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
    if ($applicable | length) == 0 and
       ($p.quotaSemantics.status == "unknown" or $p.quotaSemantics.status == "partial") then {status: "unknown"}
    elif ($applicable | length) == 0 then null
    elif ($known | length) == 0 then {status: "unknown"}
    else ($known | sort_by(
        .effectivePercentRemaining,
        if (.runway.status // "") == "exhausted_now" then 0 else 1 end
      )[0])
    end
    end
  ' 2>/dev/null
}

chosen="none"
for c in "${CANDIDATES[@]}"; do
  harness=${c%%:*}
  candidate_rest=${c#*:}
  provider=${candidate_rest%%:*}
  model=${candidate_rest#*:}
  fm_control_harness_supported "$harness" || die "unknown harness: $harness"
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
