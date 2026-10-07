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
mkdir -p "$TMP_ROOT/project"
git -C "$TMP_ROOT/project" init -q
WS_JSON=$(lab workspace create --cwd "$TMP_ROOT/project" --label fm-submitlive --no-focus) \
  || fail "could not create the isolated submit-confirm workspace"
PANE=$(printf '%s' "$WS_JSON" | jq -er '.result.root_pane.pane_id') \
  || fail "workspace create did not return a pane id"
TARGET="$SESSION:$PANE"
VERSION=$(PATH="$ORIGINAL_PATH" claude --version 2>/dev/null | head -1 || printf 'version-unknown')
HERDR_VER=$(PATH="$ORIGINAL_PATH" herdr --version 2>/dev/null | head -1 || printf 'herdr-unknown')

lab pane run "$PANE" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --dangerously-skip-permissions --settings '{\"feedbackDrafts\":\"off\"}'" >/dev/null \
  || fail "could not launch Claude Code ($VERSION) in the isolated Herdr pane"

capture() {
  lab pane read "$PANE" --source visible > "$EVIDENCE/$1.txt"
  printf '%s native=%s composer=%s\n' "$1" "$(lab agent get "$PANE" | jq -r '.result.agent.agent_status // empty')" "$(fm_backend_herdr_composer_state "$TARGET")" | tee -a "$EVIDENCE/states.txt"
}
idle=0
trusted=0
st=
composer=
i=0
while [ "$i" -lt 60 ]; do
  screen=$(lab pane read "$PANE" --source visible 2>/dev/null || true)
  case "$trusted:$screen" in
    0:*'Yes, I trust this folder'*)
      # A fresh checkout path stops on Claude's folder-trust prompt, which the
      # pre-send proof would read as a non-empty composer. Accept it once and
      # keep waiting for a real idle composer; the accepted dialog stays in the
      # viewport. The prompt preselects "No, exit", so move to "Yes" before
      # confirming; a bare Enter quits Claude.
      capture trust-dialog
      [ "$(fm_backend_herdr_composer_state "$TARGET")" != empty ] || fail "trust prompt incorrectly empty"
      pass "fresh folder-trust prompt remains pending and fails readiness"
      exit 0
      trusted=1
      lab pane send-keys "$PANE" down enter >/dev/null \
        || fail "could not accept Claude's folder-trust prompt"
      ;;
    *)
      # Ready means native idle plus the adapter's own empty-composer verdict.
      # Herdr can report the agent idle while the folder-trust prompt is still
      # up, and that prompt never reads as an empty composer. The permission
      # footer is not consulted: its wording follows the launch flag, a
      # managed policy that disables bypass mode, and shift+tab cycling.
      st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
      case "$st" in
        idle|done)
          composer=$(fm_backend_herdr_composer_state "$TARGET")
          [ "$composer" != empty ] || { idle=1; break; }
          ;;
      esac
      ;;
  esac
  i=$((i + 1))
  sleep 1
done
[ "$idle" = 1 ] \
  || fail "Claude Code ($VERSION) on $HERDR_VER never reached an idle empty composer in the lab pane (last native status '${st:-none}', composer '${composer:-unread}')"

capture ready-auto-footer
case "$screen" in *'auto mode on'*) ;; *) fail "expected current auto-mode footer for regression proof" ;; esac
case "$screen" in *'bypass permissions on'*) fail "old footer predicate unexpectedly succeeds" ;; esac
pass "current idle empty Claude rejected by the old bypass-footer predicate"
lab pane send-text "$PANE" 'UNSUBMITTEDLABDRAFT' >/dev/null
sleep 0.5
capture pending-draft
[ "$(fm_backend_herdr_composer_state "$TARGET")" = pending ] || fail "typed draft must not be empty"
lab pane send-keys "$PANE" ctrl+u >/dev/null
sleep 0.5
[ "$(fm_backend_herdr_composer_state "$TARGET")" = empty ] || fail "draft did not clear"

pass "fresh trust gate and ready-state boundaries verified"
