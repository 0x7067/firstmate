#!/usr/bin/env bash
set -eu
ROOT=$PWD
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4DK7C9KE09JXBG0DQVT0PRS
export TMPDIR="$ROOT/.test-tmp" FM_HERDR_LAB_STATE_DIR="$ROOT/.test-tmp/lab-state"
HELPER="$ROOT/bin/fm-herdr-lab.sh"
SESSION=$("$HELPER" name readiness)
ORIGINAL_PATH=$PATH
mkdir -p "$TMPDIR/manual-bin" "$TMPDIR/fresh-project"
cleanup() { PATH="$ORIGINAL_PATH" "$HELPER" teardown "$SESSION"; }
trap cleanup EXIT
cat > "$TMPDIR/manual-bin/herdr" <<WRAPPER
#!/usr/bin/env bash
set -eu
args=("\$@")
n=\${#args[@]}
[ "\${args[\$((n-2))]}" = --session ]
[ "\${args[\$((n-1))]}" = "$SESSION" ]
exec env PATH="$ORIGINAL_PATH" "$HELPER" run "$SESSION" "\${args[@]:0:\$((n-2))}"
WRAPPER
chmod +x "$TMPDIR/manual-bin/herdr"
"$HELPER" provision "$SESSION"
lab() { PATH="$ORIGINAL_PATH" "$HELPER" run "$SESSION" "$@"; }
export PATH="$TMPDIR/manual-bin:$ORIGINAL_PATH"
. "$ROOT/bin/backends/herdr.sh"
WS=$(lab workspace create --cwd "$TMPDIR/fresh-project" --label readiness --no-focus)
PANE=$(printf '%s' "$WS" | jq -er '.result.root_pane.pane_id')
TARGET="$SESSION:$PANE"
sample() {
 st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty' || true)
 composer=$(fm_backend_herdr_composer_state "$TARGET")
 ready=false
 case "$st:$composer" in idle:empty|done:empty) ready=true ;; esac
 printf '%s native=%s composer=%s ready=%s\n' "$1" "$st" "$composer" "$ready"
 lab pane read "$PANE" --source visible > "$EVIDENCE/$1-pane.txt"
 lab agent get "$PANE" > "$EVIDENCE/$1-agent.json" 2>/dev/null || true
}
lab pane run "$PANE" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --dangerously-skip-permissions --settings '{\"feedbackDrafts\":\"off\"}'" >/dev/null
for ((i=0;i<60;i++)); do
 screen=$(lab pane read "$PANE" --source visible)
 if [[ "$screen" == *'Yes, I trust this folder'* ]]; then break; fi
 sleep 1
done
sample trust
[ "$ready" = false ]
[ "$composer" != empty ]
lab pane send-keys "$PANE" down enter >/dev/null
for ((i=0;i<60;i++)); do
 sample idle > "$EVIDENCE/latest-idle-state.txt"
 [ "$ready" = true ] && break
 sleep 1
done
cat "$EVIDENCE/latest-idle-state.txt"
[ "$ready" = true ]
screen=$(cat "$EVIDENCE/idle-pane.txt")
[[ "$screen" != *'bypass permissions on'* ]]
printf 'Old footer predicate rejects this real idle/empty pane; new readiness predicate accepts it.\n'
lab pane send-text "$PANE" 'PENDING_READINESS_ADVERSARY' >/dev/null
sleep 1
sample pending
[ "$ready" = false ]
[ "$composer" = pending ]
lab pane send-keys "$PANE" ctrl+u >/dev/null
sleep 1
sample cleared
[ "$ready" = true ]
lab pane send-text "$PANE" 'Write the integers from 1 to 800, each on a separate line. Do not use tools.' >/dev/null
lab pane send-keys "$PANE" enter >/dev/null
observed=0
for ((i=0;i<40;i++)); do
 sample working > "$EVIDENCE/latest-working-state.txt"
 if [ "$st" = working ]; then
   cat "$EVIDENCE/latest-working-state.txt"
   [ "$ready" = false ]
   observed=1
   break
 fi
 sleep 0.5
done
[ "$observed" = 1 ]
printf 'All focused readiness scenarios passed against real Claude in %s.\n' "$SESSION"
