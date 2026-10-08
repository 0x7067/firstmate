#!/usr/bin/env bash
set -eu
ROOT=$PWD
E=/home/denguinho/.no-mistakes/evidence/01M4DK7C9KE09JXBG0DQVT0PRS
export FM_HERDR_LAB_STATE_DIR="$ROOT/.test-live/lab-state" TMPDIR="$ROOT/.test-live/tmp"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
helper="$ROOT/bin/fm-herdr-lab.sh"
session=$("$helper" name busy-bound)
trap '"$helper" teardown "$session"' EXIT
"$helper" provision "$session"
lab() { "$helper" run "$session" "$@"; }
. "$ROOT/bin/backends/herdr.sh"
fm_backend_herdr_cli() { local session=$1; shift; "$helper" run "$session" "$@"; }
pane=$(lab workspace create --cwd "$ROOT" --label busy-bound --no-focus | jq -er '.result.root_pane.pane_id')
target="$session:$pane"
lab pane run "$pane" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude --permission-mode auto --settings '{\"feedbackDrafts\":\"off\"}'" > /dev/null
for ((i=0;i<45;i++)); do
 st=$(lab agent get "$pane" 2>/dev/null | jq -r '.result.agent.agent_status') || st=unknown
 composer=$(fm_backend_herdr_composer_state "$target")
 if [[ "$st" == idle || "$st" == done ]] && [[ "$composer" == empty ]]; then break; fi
 sleep 1
done
printf 'initial native=%s composer=%s\n' "$st" "$composer"
fm_backend_herdr_send_text_submit "$target" 'Count from 1 to 300 with one number per line; do not use tools.' 3 0.4 0.4
for ((i=0;i<100;i++)); do
 st=$(lab agent get "$pane" | jq -r '.result.agent.agent_status')
 composer=$(fm_backend_herdr_composer_state "$target")
 printf 'sample native=%s composer=%s\n' "$st" "$composer"
 if [[ "$st" == working ]]; then
   lab pane read "$pane" --source visible --format ansi > "$E/busy.ansi"
   printf 'BUSY native=%s composer=%s; native status rejects readiness\n' "$st" "$composer"
   exit 0
 fi
 sleep 0.3
done
lab pane read "$pane" --source visible --format ansi > "$E/busy-unobserved.ansi"
exit 1
