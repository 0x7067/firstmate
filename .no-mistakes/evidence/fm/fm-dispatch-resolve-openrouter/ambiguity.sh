#!/usr/bin/env bash
set -eu
source <(sed '/^run openrouter-key-alone/,$d' .dispatch-live/drive.sh)
jq '.rules |= map(.when="A simple bug fix with a stated root cause." | .min_confidence=0.9)' "$LAB/home/config/crew-dispatch.json" > "$LAB/rules-next.json"
mv "$LAB/rules-next.json" "$LAB/home/config/crew-dispatch.json"
run duplicate-rule-ambiguity FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:?}"
