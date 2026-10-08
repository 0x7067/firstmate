#!/usr/bin/env bash
set -eu
ROOT=$PWD
EV=/home/denguinho/.no-mistakes/evidence/01M4CE93TQQAHQD97QWA2QR4XZ
export TMPDIR="$ROOT/.test-live/tmp" FM_HOME="$ROOT/.test-live/home" FM_HERDR_LAB_STATE_DIR="$ROOT/.test-live/lab-state"
SESSION=$(bin/fm-herdr-lab.sh name idle-boundaries)
ORIGINAL_PATH=$PATH
cleanup() { env PATH="$ORIGINAL_PATH" "$ROOT/bin/fm-herdr-lab.sh" teardown "$SESSION"; }
trap cleanup EXIT
bin/fm-herdr-lab.sh provision "$SESSION"
mkdir -p "$ROOT/.test-live/route"
cat > "$ROOT/.test-live/route/herdr" <<EOF
#!/usr/bin/env bash
args=("\$@")
n=\${#args[@]}
[ "\${args[n-2]}" = --session ] && [ "\${args[n-1]}" = "$SESSION" ] || exit 98
exec env PATH="$ORIGINAL_PATH" "$ROOT/bin/fm-herdr-lab.sh" run "$SESSION" "\${args[@]:0:n-2}"
EOF
chmod +x "$ROOT/.test-live/route/herdr"
export PATH="$ROOT/.test-live/route:$ORIGINAL_PATH"
. "$ROOT/bin/backends/herdr.sh"
lab() { env PATH="$ORIGINAL_PATH" "$ROOT/bin/fm-herdr-lab.sh" run "$SESSION" "$@"; }
state() {
  st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty') || st=none
  composer=$(fm_backend_herdr_composer_state "$TARGET")
  screen=$(lab pane read "$PANE" --source visible)
}
ready() { case "$st" in idle|done) [ "$composer" = empty ];; *) return 1;; esac; }
record() {
  printf '\n%s: native=%s composer=%s\n%s\n' "$1" "$st" "$composer" "$screen" >> "$EV/boundary-screens.log"
  printf '%s\n' "$screen" > "$EV/$1.txt"
}
wait_idle() {
  for ((i=0;i<60;i++)); do state; ready && return 0; sleep 1; done
  record not-ready; return 1
}
PANE=$(lab workspace create --cwd "$ROOT" --label boundaries --no-focus | jq -er '.result.root_pane.pane_id')
TARGET="$SESSION:$PANE"
lab pane run "$PANE" 'CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude --permission-mode auto --settings '\''{"feedbackDrafts":"off"}'\''' >/dev/null
wait_idle
record auto-idle
[[ "$screen" == *'auto mode on'* ]] && [[ "$screen" != *'bypass permissions on'* ]]
echo 'PASS: current auto-mode output is idle/empty while the former footer predicate rejects it'
lab pane send-text "$PANE" 'DO NOT SUBMIT: pending draft boundary' >/dev/null
sleep 1
state; record pending-draft
[ "$composer" = pending ] && ! ready
echo 'PASS: an idle agent with a typed draft cannot satisfy readiness'
lab pane send-keys "$PANE" ctrl+u >/dev/null
wait_idle
lab pane send-text "$PANE" '/newer' >/dev/null
sleep 1
state; record slash-draft
[ "$composer" = pending ] && ! ready
[ "$(fm_backend_herdr_composer_content "$TARGET")" = /newer ]
echo 'PASS: a slash draft remains pending and its exact text survives composer extraction'
lab pane send-keys "$PANE" ctrl+u >/dev/null
wait_idle
for mode in 1 2 3; do
  lab pane send-keys "$PANE" shift+tab >/dev/null
  sleep 1
  state; record "mode-$mode"
  ready || { echo 'FAIL: cycling the permission footer changed readiness'; exit 1; }
done
echo 'PASS: three permission-mode cycles preserve idle empty readiness'
TOKEN="BOUNDARYPONG$RANDOM"
fm_backend_herdr_send_text_submit "$TARGET" "Reply with exactly $TOKEN and nothing else." 3 0.4 0.4 > "$EV/boundary-submit.txt"
busy=0
for ((i=0;i<20;i++)); do
  state
  if [ "$st" = working ]; then
    record working-empty
    [ "$composer" = empty ]
    ! ready
    busy=1
    break
  fi
  sleep 0.2
done
[ "$busy" = 1 ]
echo 'PASS: a real working turn cannot satisfy readiness even after its composer clears'
wait_idle
record reply-idle
[[ "$screen" == *"● $TOKEN"* ]]
verdict=$(fm_backend_herdr_send_text_submit "$TARGET" '/exit' 3 0.4 1.2)
[ "$verdict" != send-failed ]
echo "PASS: boundary-session /exit submission returned $verdict"
mkdir -p "$ROOT/.test-live/untrusted"
git init -q "$ROOT/.test-live/untrusted"
PANE=$(lab workspace create --cwd "$ROOT/.test-live/untrusted" --label trust-boundary --no-focus | jq -er '.result.root_pane.pane_id')
TARGET="$SESSION:$PANE"
lab pane run "$PANE" 'claude --permission-mode auto' >/dev/null
seen=0
for ((i=0;i<30;i++)); do
  state
  if [[ "$screen" == *'Yes, I trust this folder'* ]]; then
    record folder-trust
    [ "$composer" != empty ] && ! ready
    seen=1
    break
  fi
  sleep 1
done
[ "$seen" = 1 ] || { record missing-trust; echo 'FAIL: no trust dialog rendered'; exit 1; }
echo 'PASS: the real folder-trust dialog is not an idle empty composer; no trust setting was changed'
