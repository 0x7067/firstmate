#!/usr/bin/env bash
set -eu
ROOT=$PWD
E=/home/denguinho/.no-mistakes/evidence/01M4DK7C9KE09JXBG0DQVT0PRS
export TMPDIR="$ROOT/.test-tmp" FM_HERDR_LAB_STATE_DIR="$ROOT/.test-tmp/lab-state"
ORIGINAL_PATH=$PATH
HELPER="$ROOT/bin/fm-herdr-lab.sh"
SESSION=$("$HELPER" name readiness-adversarial)
mkdir -p "$ROOT/.test-tmp/wrapper" "$ROOT/.test-tmp/fresh-repo-final"
git init -q "$ROOT/.test-tmp/fresh-repo-final"
trap 'PATH="$ORIGINAL_PATH" "$HELPER" teardown "$SESSION"' EXIT
cat > "$ROOT/.test-tmp/wrapper/herdr" <<WRAP
#!/usr/bin/env bash
args=("\$@")
n=\${#args[@]}
[ "\${args[n-2]}" = --session ] && [ "\${args[n-1]}" = "$SESSION" ] || exit 97
exec env PATH="$ORIGINAL_PATH" "$HELPER" run "$SESSION" "\${args[@]:0:n-2}"
WRAP
chmod +x "$ROOT/.test-tmp/wrapper/herdr"
"$HELPER" provision "$SESSION"
export PATH="$ROOT/.test-tmp/wrapper:$ORIGINAL_PATH"
. "$ROOT/bin/backends/herdr.sh"
lab() { env PATH="$ORIGINAL_PATH" "$HELPER" run "$SESSION" "$@"; }
PANE=$(lab workspace create --cwd "$ROOT/.test-tmp/fresh-repo-final" --label readiness --no-focus | jq -er '.result.root_pane.pane_id')
TARGET="$SESSION:$PANE"
observe() {
  st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
  composer=$(fm_backend_herdr_composer_state "$TARGET")
  screen=$(lab pane read "$PANE" --source visible)
  ready=no
  case "$st:$composer" in idle:empty|done:empty) ready=yes;; esac
  printf '%s native=%s composer=%s ready=%s\n' "$1" "$st" "$composer" "$ready"
}
snapshot() {
  lab pane read "$PANE" --source visible > "$E/$1.txt"
  lab pane read "$PANE" --source visible --format ansi > "$E/$1.ansi"
  lab agent get "$PANE" > "$E/$1-agent.json"
}
lab pane run "$PANE" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --permission-mode auto --settings '{\"feedbackDrafts\":\"off\"}'" >/dev/null
for i in $(seq 1 60); do
  screen=$(lab pane read "$PANE" --source visible)
  case "$screen" in *'Yes, I trust this folder'*) break;; esac
  sleep 1
done
observe trust-dialog
snapshot trust-dialog
[ "$ready" = no ] && [ "$composer" != empty ]
lab pane send-keys "$PANE" down enter >/dev/null
for i in $(seq 1 60); do
  observe after-trust
  [ "$ready" != yes ] || break
  sleep 1
done
[ "$ready" = yes ]
snapshot idle-auto
case "$screen" in *'bypass permissions on'*) echo 'baseline condition unexpectedly satisfied'; exit 1;; esac
# Run the old permission-footer readiness rule through its actual 60-second budget.
baseline=timeout
for i in $(seq 1 60); do
  screen=$(lab pane read "$PANE" --source visible)
  case "$screen" in *'bypass permissions on'*)
    st=$(lab agent get "$PANE" | jq -r '.result.agent.agent_status // empty')
    case "$st" in idle|done) baseline=ready; break;; esac;; esac
  sleep 1
done
echo "old-footer-wait=$baseline"
[ "$baseline" = timeout ]
observe new-wait
[ "$ready" = yes ]
lab pane send-text "$PANE" 'DO NOT SUBMIT: retained draft' >/dev/null
sleep 1
observe pending-draft
snapshot pending-draft
[ "$ready" = no ] && [ "$composer" = pending ]
lab pane send-keys "$PANE" ctrl-u >/dev/null
sleep 1
observe cleared-draft
[ "$ready" = yes ]
# Cycle modes without making a global configuration change.
lab pane send-keys "$PANE" shift-tab >/dev/null
sleep 1
observe cycled-mode
snapshot cycled-mode
[ "$ready" = yes ]
verdict=$(fm_backend_herdr_send_text_submit "$TARGET" 'Think carefully about the sum of all integers from 1 to 100000, then reply with just that sum. Do not use any tools.' 3 0.4 0.4)
echo "working-request-submit=$verdict"
working=no
for i in $(seq 1 30); do
  observe in-turn
  case "$st" in working|thinking|running) working=yes; snapshot working-empty; [ "$ready" = no ]; break;; esac
  sleep 0.2
done
[ "$working" = yes ]
echo 'PASS: trust, auto readiness, old timeout, pending draft, cleared draft, permission cycling, working rejection'
