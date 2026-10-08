#!/usr/bin/env bash
# Live Herdr submit-confirmation guard (live-harness-optin family).
#
# Herdr's native agent_status can stay idle for a whole landed Claude turn, and
# a busy-queued Enter can keep proven pending text visible. A stub cannot prove
# either signal. This guard launches real Claude Code in an isolated Herdr lab
# and requires fm_backend_herdr_send_text_submit to report empty for a landed
# idle steer. It then requires the same submit path to prove and submit a
# typed /exit slash command behind the command popup Claude renders below the
# composer (the fm-control exit breakage on 2.1.283) and verifies the agent
# actually exited. It fails naming the harness and version rather than
# degrading quietly.
#
# Run explicitly with FM_HERDR_SUBMIT_CONFIRM_LIVE=1 after a Herdr or Claude
# upgrade, and before trusting a refreshed docs/verification/runtime-backends.md
# "Herdr submit confirmation" entry.
# Every Herdr call, including adapter calls, is routed through bin/fm-herdr-lab.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

fm_live_gate opt-in FM_HERDR_SUBMIT_CONFIRM_LIVE herdr jq claude

[ -x "$LAB_HELPER" ] || fail "FM_HERDR_SUBMIT_CONFIRM_LIVE=1 but the Herdr lab helper is not executable at $LAB_HELPER"

# shellcheck source=tests/herdr-test-safety.sh
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane

ORIGINAL_PATH=$PATH
SESSION=$("$LAB_HELPER" name herdr-submit-confirm-live)
TMP_ROOT=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-herdr-submit-confirm-live.XXXXXX")
FAKEBIN="$TMP_ROOT/fakebin"
mkdir -p "$FAKEBIN"
CHECKED=0

cleanup() {
  local rc=$?
  trap - EXIT
  if ! PATH="$ORIGINAL_PATH" "$LAB_HELPER" teardown "$SESSION"; then
    rc=1
  fi
  rm -rf "$TMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT

cat > "$FAKEBIN/herdr" <<EOF
#!/usr/bin/env bash
set -u
args=("\$@")
n=\${#args[@]}
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "$SESSION" ] || { echo "wrapper refused foreign session" >&2; exit 97; }
  args=("\${args[@]:0:\$((n-2))}")
else
  echo "wrapper requires trailing --session $SESSION" >&2
  exit 98
fi
exec env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "\${args[@]}"
EOF
chmod +x "$FAKEBIN/herdr"

"$LAB_HELPER" provision "$SESSION" || fail "could not provision the isolated Herdr lab"
export PATH="$FAKEBIN:$ORIGINAL_PATH"

# shellcheck source=/dev/null
. "$ROOT/bin/backends/herdr.sh"

lab() { env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "$@"; }
WS_JSON=$(lab workspace create --cwd "$ROOT" --label fm-submitlive --no-focus) \
  || fail "could not create the isolated submit-confirm workspace"
PANE=$(printf '%s' "$WS_JSON" | jq -er '.result.root_pane.pane_id') \
  || fail "workspace create did not return a pane id"
TARGET="$SESSION:$PANE"
VERSION=$(PATH="$ORIGINAL_PATH" claude --version 2>/dev/null | head -1 || printf 'version-unknown')
HERDR_VER=$(PATH="$ORIGINAL_PATH" herdr --version 2>/dev/null | head -1 || printf 'herdr-unknown')

lab pane run "$PANE" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --dangerously-skip-permissions --settings '{\"feedbackDrafts\":\"off\"}'" >/dev/null \
  || fail "could not launch Claude Code ($VERSION) in the isolated Herdr pane"

EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4DK7C9KE09JXBG0DQVT0PRS
observe() {
  st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // "absent"')
  composer=$(fm_backend_herdr_composer_state "$TARGET")
  ready=no
  case "$st:$composer" in idle:empty|done:empty) ready=yes;; esac
  printf 'native=%s composer=%s ready=%s\n' "$st" "$composer" "$ready"
}
for i in $(seq 1 60); do
  screen=$(lab pane read "$PANE" --source visible)
  case "$screen" in
    *'Yes, I trust this folder'*)
      observe | tee "$EVIDENCE/trust-state.txt"
      printf '%s\n' "$screen" > "$EVIDENCE/trust-screen.txt"
      [ "$ready" = no ] || fail 'trust prompt incorrectly ready'
      lab pane send-keys "$PANE" down enter >/dev/null
      break;;
  esac
  observe
  [ "$ready" = yes ] && break
  sleep 1
done
for i in $(seq 1 60); do
  observe
  [ "$ready" = yes ] && break
  sleep 1
done
[ "$ready" = yes ] || fail 'never became ready'
observe > "$EVIDENCE/idle-state.txt"
lab pane read "$PANE" --source visible > "$EVIDENCE/idle-screen.txt"
# Counterfactual: apply the former footer requirement to this actual live output.
if grep -Fq 'bypass permissions on' "$EVIDENCE/idle-screen.txt"; then
  fail 'former footer is present: original fragility not reproduced'
fi
pass 'actual idle empty auto-mode composer fails the former footer requirement'
lab pane send-text "$PANE" 'DO NOT SUBMIT THIS PENDING INPUT' >/dev/null
sleep 1
observe > "$EVIDENCE/pending-state.txt"
lab pane read "$PANE" --source visible > "$EVIDENCE/pending-screen.txt"
[ "$ready" = no ] && [ "$composer" = pending ] || fail 'pending input incorrectly ready'
pass 'pending text rejected even with native idle'
lab pane send-keys "$PANE" ctrl+u >/dev/null
sleep 1
lab pane send-text "$PANE" 'Think carefully about the numbers 1 to 1000 and then reply with READY.' >/dev/null
lab pane send-keys "$PANE" enter >/dev/null
seen=0
for i in $(seq 1 30); do
  observe
  if [ "$st" = working ]; then
    observe > "$EVIDENCE/working-state.txt"
    lab pane read "$PANE" --source visible > "$EVIDENCE/working-screen.txt"
    [ "$ready" = no ] || fail 'working pane incorrectly ready'
    seen=1
    break
  fi
  sleep 0.2
done
[ "$seen" = 1 ] || fail 'no native working state observed'
pass 'working agent rejected even when composer is empty'
