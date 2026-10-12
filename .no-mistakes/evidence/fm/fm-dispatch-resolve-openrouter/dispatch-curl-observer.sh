#!/usr/bin/env bash
set -u
header=$(cat /dev/fd/3)
key=${header#Authorization: Bearer }
argv_clean=true
for arg in "$@"; do
  if [[ -n "$key" && "$arg" == *"$key"* ]]; then argv_clean=false; fi
done
env_clean=true
for name in TYPESAFE_API_KEY TYPESAFE_API_KEY_PRIVATE OPENROUTER_API_KEY OPENROUTER_API_KEY_PRIVATE; do
  if [[ -v $name ]]; then env_clean=false; fi
done
printf 'real curl audit: argv_secret_free=%s child_environment_secret_free=%s bearer_header_present=%s\n' "$argv_clean" "$env_clean" "$([[ -n "$key" ]] && echo true || echo false)" >> "${DISPATCH_AUDIT_LOG:?}"
/usr/bin/curl "$@" 3< <(printf '%s\n' "$header")
