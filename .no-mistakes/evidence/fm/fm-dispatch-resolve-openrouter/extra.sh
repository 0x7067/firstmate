#!/usr/bin/env bash
set -eu
source <(sed '/^run openrouter-key-alone/,$d' .dispatch-live/drive.sh)
printf '%s\n' FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=invalid-model-to-override > "$LAB/home/.env"
run env-model-wins FM_DISPATCH_MODEL=typesafe/jev-1.13 "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:?}"
rm "$LAB/home/.env"
jq '.rules[0].approval="captain"' "$LAB/home/config/crew-dispatch.json" > "$LAB/rules-next.json"
mv "$LAB/rules-next.json" "$LAB/home/config/crew-dispatch.json"
run captain-approval FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:?}"
run invalid-model FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=nonexistent/disposable-validation-model "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:?}"
printf '%s\n' '# Task' 'Investigate the project and decide what to do.' > "$LAB/brief.md"
run vague-brief FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:?}"
