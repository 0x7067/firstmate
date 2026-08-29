#!/usr/bin/env bash
# fm-deepseek-peak.sh - report whether DeepSeek is currently in peak pricing.
#
# Usage: fm-deepseek-peak.sh [--quiet|--exit]
#   default: print human-readable status and exit 0 (off-peak) or 1 (peak)
#   --quiet:  exit 0 if off-peak, 1 if peak, with no output
#   --exit:   exit 0 if off-peak, 1 if peak, print one-line status
#
# Peak windows from deepseek-peak-pricing extension: Beijing 09:00-12:00 and
# 14:00-18:00 (UTC+8). The script converts current UTC to Beijing hour and
# reports peak/off-peak plus the next transition in local time.

set -euo pipefail

quiet=0
exit_only=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) quiet=1 ;;
    --exit)  exit_only=1 ;;
    --help|-h)
      sed -n '1,/^#/!d;p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *)
      echo "usage: $0 [--quiet|--exit]" >&2
      exit 2
      ;;
  esac
  shift
done

# Beijing is UTC+8; normalize to 0-23.
beijing_hour=$(( ($(date -u +%H) + 8) % 24 ))

# Peak windows in Beijing time: 09-12 and 14-18.
in_peak=0
if [[ $beijing_hour -ge 9 && $beijing_hour -lt 12 ]] || [[ $beijing_hour -ge 14 && $beijing_hour -lt 18 ]]; then
  in_peak=1
fi

# Compute next transition in local time.
# Beijing peak end hours: 12 and 18. Peak start hours: 9 and 14.
if [[ $in_peak -eq 1 ]]; then
  if [[ $beijing_hour -ge 9 && $beijing_hour -lt 12 ]]; then
    next_beijing=12
  else
    next_beijing=18
  fi
  label="PEAK"
  transition_word="ends"
else
  if [[ $beijing_hour -lt 9 ]]; then
    next_beijing=9
  elif [[ $beijing_hour -lt 14 ]]; then
    next_beijing=14
  else
    next_beijing=9  # tomorrow
  fi
  label="Off-Peak"
  transition_word="starts"
fi

# Convert Beijing transition hour to today's UTC, then to local time string.
utc_hour=$(( (next_beijing - 8 + 24) % 24 ))
# If the Beijing time has already passed today in local terms, add 24h.
local_ts=$(date -u -d "today ${utc_hour}:00:00 UTC" +%s 2>/dev/null || date -u -j -f "%H:%M:%S" "${utc_hour}:00:00" +%s 2>/dev/null)
now_ts=$(date -u +%s)
if [[ $local_ts -lt $now_ts ]]; then
  local_ts=$(( local_ts + 86400 ))
fi
local_time=$(date -d "@${local_ts}" +%H:%M 2>/dev/null || date -r "${local_ts}" +%H:%M)

if [[ $quiet -eq 1 ]]; then
  exit "$in_peak"
fi

if [[ $exit_only -eq 1 ]]; then
  echo "DeepSeek ${label} · ${transition_word} ${local_time} local"
  exit "$in_peak"
fi

echo "DeepSeek ${label} (Beijing ${beijing_hour}:00) · ${transition_word} ${local_time} local"
exit "$in_peak"
