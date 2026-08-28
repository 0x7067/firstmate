#!/usr/bin/env bash
# Quota-exhaustion process-event adapter.
#
# Usage:
#   fm-procevent-quota.sh arm [--interval <secs>] [--threshold <percent>] [--provider <provider>]
#   fm-procevent-quota.sh poll
#   fm-procevent-quota.sh classify <result-file>
#   fm-procevent-quota.sh terminal <result-file>
#   fm-procevent-quota.sh source-id
#   fm-procevent-quota.sh retire
#
# arm        Register a recurring quota-axi --json poll that wakes firstmate
#            when the tracked provider's effectivePercentRemaining drops below
#            <threshold> (default 10%) or when its runway.status becomes
#            exhausted_now. The condition is deterministic, the action is only
#            the durable `check: procevent:quota:<seq>` wake, and the watch is
#            registered through `bin/fm-procevent.sh register`.
# poll       The blocking child the generic runner executes; never run this
#            directly in a conversational turn. It runs `quota-axi --json` once,
#            evaluates the condition, and prints a one-line result document.
# classify   Print the captured outcome class: low, exhausted, error, or unknown.
# terminal   Every quota poll is terminal because the source fires at most once.
# source-id  Print the canonical source id.
# retire     Stop the watch and retire the registration.
#
# The canonical source id is `quota` for the aggregate tracked provider.
# A provider named with --provider sets the tracked provider and the source id
# becomes `quota-<provider>`.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

# shellcheck source=bin/fm-pr-lib.sh
. "$SCRIPT_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-procevent-lib.sh
. "$SCRIPT_DIR/fm-procevent-lib.sh"
# shellcheck source=bin/fm-quota-axi-lib.sh
. "$SCRIPT_DIR/fm-quota-axi-lib.sh"
# shellcheck source=bin/fm-timeout-lib.sh
. "$SCRIPT_DIR/fm-timeout-lib.sh"

DEFAULT_INTERVAL=60
DEFAULT_THRESHOLD=10

SOURCE_ID_BASE=quota

CANONICAL_SOURCE_ID=
PROVIDER=

usage() { sed -n '2,37p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }
die() { printf 'error: %s\n' "$1" >&2; exit 1; }

resolve_provider() {
  PROVIDER=${1:-}
  if [ -n "$PROVIDER" ]; then
    case "$PROVIDER" in
      ''|*[!a-z0-9-]*) die "invalid provider: $PROVIDER" ;;
    esac
    CANONICAL_SOURCE_ID="$SOURCE_ID_BASE-$PROVIDER"
  else
    CANONICAL_SOURCE_ID=$SOURCE_ID_BASE
    PROVIDER=
  fi
  fm_procevent_source_id_valid "$CANONICAL_SOURCE_ID" || die "source id is not path-safe: $CANONICAL_SOURCE_ID"
}

positive_number() {
  local n=${1-}
  local LC_ALL=C
  [[ "$n" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
  [ "$n" != 0 ] && [[ ! "$n" =~ ^0+(\.0+)?$ ]]
}

positive_int() { case "${1-}" in ''|*[!0-9]*) return 1 ;; 0) return 1 ;; *) return 0 ;; esac }

valid_percent() {
  local n=${1-}
  local LC_ALL=C
  [[ "$n" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
  [ "${n%.*}" -le 100 ] || return 1
}

# quota_json [timeout]
# Run `quota-axi --json` bounded by the given timeout. A missing or incompatible
# quota-axi is an error condition, not a signal to fire.
quota_json() {
  local timeout=${1:-} output
  if [ -n "$timeout" ]; then
    fm_quota_axi_compatible "$timeout" >/dev/null 2>&1 || return 2
    if command -v timeout >/dev/null 2>&1; then
      output=$(timeout "$timeout" quota-axi --json 2>/dev/null </dev/null) || return 2
    elif command -v gtimeout >/dev/null 2>&1; then
      output=$(gtimeout "$timeout" quota-axi --json 2>/dev/null </dev/null) || return 2
    elif command -v perl >/dev/null 2>&1; then
      output=$(perl -e 'my $t = shift; my $pid = fork; die "fork failed" unless defined $pid; if (!$pid) { setpgrp(0, 0); exec @ARGV } local $SIG{ALRM} = sub { kill "TERM", -$pid; select undef, undef, undef, 0.2; kill "KILL", -$pid; exit 124 }; alarm $t; waitpid $pid, 0; exit($? >> 8)' "$timeout" quota-axi --json 2>/dev/null </dev/null) || return 2
    else
      return 2
    fi
  else
    fm_quota_axi_compatible >/dev/null 2>&1 || return 2
    output=$(quota-axi --json 2>/dev/null </dev/null) || return 2
  fi
  printf '%s\n' "$output"
}

# evaluate_condition <json> [provider] [threshold]
# Read the JSON and return:
#   0 if quota is exhausted_now or effectivePercentRemaining <= threshold
#   1 if quota is healthy (above threshold and not exhausted_now)
#   2 on error / unparseable / missing provider
evaluate_condition() {
  local json=$1 provider=${2:-} threshold=${3:-$DEFAULT_THRESHOLD}
  local status
  status=$(printf '%s\n' "$json" | jq -r --arg provider "$provider" --argjson threshold "$threshold" '
    if (.providers // null) == null then "error"
    else
      (.providers[]? | select(.provider == $provider)) as $p |
      if $provider != "" and ($p // null) == null then "missing_provider"
      else
        (
          ($p.quotaSemantics.effectiveAvailability // []) |
          map(select(.status == "known" and
            (.runway.status // "") != "exhausted_now" and
            .effectivePercentRemaining > $threshold
          )) |
          if length == 0 then "trigger" else "ok" end
        ) // (
          ($p.quotaSemantics.effectiveAvailability // []) |
          map(select(.status == "known")) |
          if length == 0 then "error" else "trigger" end
        )
      end
    end
  ' 2>/dev/null) || { printf 'error\n'; return 2; }
  case "$status" in
    ok) return 1 ;;
    trigger) return 0 ;;
    *) return 2 ;;
  esac
}

# details <json> [provider]
# Print a one-line summary of the quota state for the result document.
details() {
  local json=$1 provider=${2:-}
  printf '%s\n' "$json" | jq -c --arg provider "$provider" '
    (.providers[]? | select(.provider == $provider)) as $p |
    if $provider == "" then
      {
        provider: "aggregate",
        summary: [
          (.providers[]? |
            { provider: .provider,
              best: ((.quotaSemantics.effectiveAvailability // []) |
                map(select(.status == "known")) |
                min_by(.effectivePercentRemaining) // null)
            }
          )
        ]
      }
    else
      {
        provider: $provider,
        best: (($p.quotaSemantics.effectiveAvailability // []) |
          map(select(.status == "known")) |
          min_by(.effectivePercentRemaining) // null)
      }
    end
  ' 2>/dev/null
}

cmd_source_id() {
  resolve_provider "${1-}"
  printf '%s\n' "$CANONICAL_SOURCE_ID"
}

cmd_arm() {
  local interval=$DEFAULT_INTERVAL threshold=$DEFAULT_THRESHOLD
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --interval)  positive_number "${2-}" || die "--interval needs a positive number"; interval=$2; shift 2 ;;
      --threshold) valid_percent "${2-}" || die "--threshold needs a percent 0-100"; threshold=$2; shift 2 ;;
      --provider)  resolve_provider "${2-}"; shift 2 ;;
      *) usage ;;
    esac
  done
  resolve_provider "$PROVIDER"
  fm_quota_axi_compatible 5 >/dev/null 2>&1 || die "quota-axi is missing or below the compatibility floor"
  local timeout
  timeout=$(perl -e 'print int($ARGV[0] * 0.8 + 0.5)' "$interval") || timeout=30
  [ "$timeout" -ge 5 ] || timeout=5
  "$SCRIPT_DIR/fm-procevent.sh" register quota "$CANONICAL_SOURCE_ID" \
    -- "$SCRIPT_DIR/fm-procevent-quota.sh" poll --interval "$interval" --threshold "$threshold" --provider "$PROVIDER" --timeout "$timeout" || exit 1
  printf 'armed: %s\n' "$CANONICAL_SOURCE_ID"
  printf 'provider: %s\n' "${PROVIDER:-(aggregate)}"
  printf 'threshold: %s%%\n' "$threshold"
  printf 'interval: %ss\n' "$interval"
}

# For use inside the runner: parse the spec argv and run one condition evaluation.
# This is intentionally not the public `arm` path; the runner calls this command
# directly, so the argv must match the registration.
cmd_poll() {
  local interval=$DEFAULT_INTERVAL threshold=$DEFAULT_THRESHOLD timeout=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --interval)  interval=$2; shift 2 ;;
      --threshold) threshold=$2; shift 2 ;;
      --provider)  PROVIDER=$2; shift 2 ;;
      --timeout)   timeout=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  resolve_provider "$PROVIDER"
  local json detail
  json=$(quota_json "${timeout:-}")
  case "$?" in
    0) : ;;
    *)
      printf 'quota: %s\n' "$CANONICAL_SOURCE_ID"
      printf 'status: error\n'
      printf 'detail: quota-axi --json failed or quota-axi is missing/incompatible\n'
      printf 'condition_polls: 1\n'
      exit 0
      ;;
  esac
  detail=$(details "$json" "$PROVIDER")
  if evaluate_condition "$json" "$PROVIDER" "$threshold"; then
    printf 'quota: %s\n' "$CANONICAL_SOURCE_ID"
    printf 'status: exhausted\n'
    printf 'detail: %s\n' "$detail"
    printf 'condition_polls: 1\n'
  else
    printf 'quota: %s\n' "$CANONICAL_SOURCE_ID"
    printf 'status: low\n'
    printf 'detail: %s\n' "$detail"
    printf 'condition_polls: 1\n'
  fi
  exit 0
}

cmd_classify() {
  local file=${1-} status
  [ -n "$file" ] || usage
  [ -f "$file" ] || die "result file does not exist: $file"
  status=$(awk '
    $0 == "output:" { exit }
    /^status: / { sub(/^status: /, ""); print; exit }
  ' "$file")
  case "$status" in
    low|exhausted|error) printf '%s\n' "$status" ;;
    *) printf 'unknown\n' ;;
  esac
}

cmd_terminal() {
  local file=${1-}
  [ -n "$file" ] || usage
  [ -f "$file" ] || die "result file does not exist: $file"
  [ "$(cmd_classify "$file")" != unknown ]
}

cmd_retire() {
  local id
  resolve_provider "${1-}"
  id=$CANONICAL_SOURCE_ID
  "$SCRIPT_DIR/fm-procevent.sh" retire "$id"
}

case "${1-}" in
  arm)       shift; cmd_arm "$@" ;;
  poll)      shift; [ "$#" -eq 0 ] && usage; cmd_poll "$@" ;;
  classify)  shift; cmd_classify "$@" ;;
  terminal)  shift; cmd_terminal "$@" ;;
  source-id) shift; cmd_source_id "${1-}" ;;
  retire)    shift; cmd_retire "${1-}" ;;
  ''|-h|--help|help) usage ;;
  *) die "unknown command: $1" ;;
esac
