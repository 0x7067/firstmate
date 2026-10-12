#!/usr/bin/env bash
set -u
ROOT=$PWD
LAB=$ROOT/.test-dispatch-live
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4RHZM3WT458H2KSJ9GPHHQ9
PATH="$LAB/bin:/usr/bin:/bin:$(dirname "$(mise which node)")"
export PATH
export FM_HOME="$LAB/home" FM_CONFIG_OVERRIDE="$LAB/home/config" FM_ROOT_OVERRIDE="$ROOT" TMPDIR="$LAB/tmp"
export HOME="$LAB/home" XDG_CONFIG_HOME="$LAB/xdg" XDG_CACHE_HOME="$LAB/cache" CLAUDE_CONFIG_DIR="$LAB/home/claude" CODEX_HOME="$LAB/home/codex"
unset QUOTA_AXI_SNAPSHOT FM_DISPATCH_PROVIDER FM_DISPATCH_MODEL
rm -f "$FM_HOME/.env"
cat > "$LAB/brief.md" <<'MD'
## Captain's intent
Fix the pager off-by-one bug. The known root cause is <= rather than < in the loop. Change that comparison and verify one page per call.
## Firstmate spec
Apply the single comparison correction and verify the boundary with two pages.
MD
cat > "$FM_HOME/config/crew-dispatch.json" <<'JSON'
{"rules":[{"when":"Fixing a small bug with a known root cause.","use":{"harness":"claude","model":"sonnet"}},{"when":"Generating images.","use":{"harness":"claude","model":"opus"}}],"default":{"harness":"claude","model":"sonnet"}}
JSON
run_case() {
  local name=$1
  shift
  printf '\nSCENARIO: %s\n' "$name"
  "$@" > "$LAB/stdout" 2> "$LAB/stderr"
  local rc=$?
  printf 'exit: %s\nstdout:\n' "$rc"
  cat "$LAB/stdout"
  printf 'stderr:\n'
  cat "$LAB/stderr"
}
{
run_case 'OpenRouter key alone retains default off gate' env -u TYPESAFE_API_KEY bin/fm-dispatch-resolve.sh "$LAB/brief.md"
run_case 'OpenRouter requires model' env FM_DISPATCH_PROVIDER=openrouter bin/fm-dispatch-resolve.sh "$LAB/brief.md"
run_case 'Unknown provider rejected' env FM_DISPATCH_PROVIDER=unknown bin/fm-dispatch-resolve.sh "$LAB/brief.md"
run_case 'Explicit OpenRouter without key stays off' env -u OPENROUTER_API_KEY FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 bin/fm-dispatch-resolve.sh "$LAB/brief.md"
printf 'disposable-pager\n' > "$FM_HOME/config/dispatch-never-send"
run_case 'Never-send project withholds real configured provider request' env FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 bin/fm-dispatch-resolve.sh "$LAB/brief.md" --project disposable-pager
rm "$FM_HOME/config/dispatch-never-send"
run_case 'Real OpenRouter Choice response with isolated unknown quota' env FM_DISPATCH_PROVIDER=openrouter FM_DISPATCH_MODEL=typesafe/jev-1.13 bin/fm-dispatch-resolve.sh "$LAB/brief.md" --project disposable-pager
printf '%s\n' 'FM_DISPATCH_PROVIDER=openrouter' 'FM_DISPATCH_MODEL=typesafe/jev-1.13' > "$FM_HOME/.env"
run_case 'Provider and model from home .env with process key' bin/fm-dispatch-resolve.sh "$LAB/brief.md" --project disposable-pager
run_case 'Real OpenRouter authentication failure stays nonblocking' env OPENROUTER_API_KEY=disposable-invalid-key bin/fm-dispatch-resolve.sh "$LAB/brief.md"
run_case 'Environment provider overrides home .env' env -u TYPESAFE_API_KEY FM_DISPATCH_PROVIDER=typesafe bin/fm-dispatch-resolve.sh "$LAB/brief.md"
printf '%s\n' 'OPENROUTER_API_KEY=disposable-invalid-home-key' >> "$FM_HOME/.env"
run_case 'Home .env credential is consumed when process key is absent' env -u OPENROUTER_API_KEY bin/fm-dispatch-resolve.sh "$LAB/brief.md"
run_case 'Process credential overrides invalid home .env credential' bin/fm-dispatch-resolve.sh "$LAB/brief.md"
run_case 'Process model overrides home .env model and real API rejects it safely' env FM_DISPATCH_MODEL=disposable-invalid-model bin/fm-dispatch-resolve.sh "$LAB/brief.md"
} > "$EVIDENCE/dispatch-live-cli.log"
