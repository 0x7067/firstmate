#!/usr/bin/env bash
set -eu
LAB="$PWD/.dispatch-live"
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4REP4HJRYKYJ683YMTXKEA5
export TMPDIR="$LAB/tmp"
cat > "$LAB/brief.md" <<'MD'
# Task
## Captain's intent
Fix the off-by-one in the pager. The stated root cause is <= where < was intended. Change that comparison only.
## Firstmate spec
Make the single comparison correction and verify one page per call.
MD
cat > "$LAB/home/config/crew-dispatch.json" <<'JSON'
{"rules":[{"when":"A simple bug fix with a stated root cause.","use":{"harness":"claude","model":"sonnet"}},{"when":"The task generates images.","use":{"harness":"codex","model":"gpt-5.6-sol"}}],"default":{"harness":"claude","model":"opus"}}
JSON
run() {
  local name=$1; shift
  set +e
  env -i PATH="$LAB/bin:/home/denguinho/.local/share/mise/installs/node/lts/bin:/usr/bin:/bin" HOME="$LAB/home" XDG_CONFIG_HOME="$LAB/home/config" XDG_CACHE_HOME="$LAB/cache" CODEX_HOME="$LAB/home/codex" CLAUDE_CONFIG_DIR="$LAB/home/claude" TMPDIR="$LAB/tmp" QUOTA_AXI_SNAPSHOT="$LAB/quota-cache.json" FM_HOME="$LAB/home" "$@" bash bin/fm-dispatch-resolve.sh "$LAB/brief.md" --project disposable-pager > "$LAB/out" 2> "$LAB/err"
  local status=$?
  set -e
  { printf 'Scenario: %s\nExit: %s\nstdout:\n' "$name" "$status"; cat "$LAB/out"; printf 'stderr:\n'; cat "$LAB/err"; } > "$EVIDENCE/$name.txt"
  cat "$EVIDENCE/$name.txt"
}
run openrouter-key-alone OPENROUTER_API_KEY=disposable-invalid-key
run missing-model FM_DISPATCH_PROVIDER=openrouter OPENROUTER_API_KEY=disposable-invalid-key
run unknown-provider FM_DISPATCH_PROVIDER=unknown
run missing-key FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13
printf '%s\n' disposable-pager > "$LAB/home/config/dispatch-never-send"
run never-send FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 OPENROUTER_API_KEY=disposable-invalid-key
rm "$LAB/home/config/dispatch-never-send"
run invalid-key FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 OPENROUTER_API_KEY=disposable-invalid-key
run openrouter-live FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:?}"
printf '%s\n' FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 OPENROUTER_API_KEY=disposable-invalid-key > "$LAB/home/.env"
run dotenv-invalid-key
run dotenv-env-key-wins "OPENROUTER_API_KEY=${OPENROUTER_API_KEY:?}"
run env-provider-wins FM_DISPATCH_PROVIDER=typesafe FM_DISPATCH_MODEL=jev-latest "TYPESAFE_API_KEY=${TYPESAFE_API_KEY:?}"
rm "$LAB/home/.env"
run legacy-typesafe "TYPESAFE_API_KEY=${TYPESAFE_API_KEY:?}" FM_DISPATCH_MODEL=deliberately-ignored
