#!/usr/bin/env bash
set -eu
E=/home/denguinho/.no-mistakes/evidence/01M4REP4HJRYKYJ683YMTXKEA5
expect() { rg -q -- "$2" "$E/$1.txt" || { echo "FAIL: $1 missing expected behavior"; exit 1; }; }
for s in openrouter-live dotenv-env-key-wins env-model-wins; do
 expect "$s" 'status: clear'
 expect "$s" "profile: --harness 'claude' --model 'sonnet'"
done
expect openrouter-key-alone 'TYPESAFE_API_KEY absent'
expect missing-model 'Exit: 2'
expect unknown-provider 'Exit: 2'
expect missing-key 'OPENROUTER_API_KEY absent'
expect never-send 'nothing sent'
expect invalid-key 'reason: http 401'
expect dotenv-invalid-key 'reason: http 401'
expect invalid-model 'reason: http 400'
expect env-provider-wins 'authentication_error'
expect legacy-typesafe 'authentication_error'
expect captain-approval 'status: escalate'
expect duplicate-rule-ambiguity 'status: ambiguous'
expect vague-brief "profile: --harness 'claude' --model 'opus'"
for s in captain-approval duplicate-rule-ambiguity; do
 if rg -q '  profile:' "$E/$s.txt"; then echo "FAIL: $s emitted a dispatch profile"; exit 1; fi
done
for f in "$E"/*.txt; do
 output=$(cat "$f")
 for secret in "${OPENROUTER_API_KEY:?}" "${TYPESAFE_API_KEY:?}"; do
  if [[ "$output" == *"$secret"* ]]; then echo 'FAIL: evidence contains an API key'; exit 1; fi
 done
done
echo 'Observed CLI outputs satisfy the scenario assertions; evidence contains neither supplied API key.'
