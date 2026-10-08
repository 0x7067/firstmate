#!/usr/bin/env bash
set -eu
ROOT=$PWD
E=/home/denguinho/.no-mistakes/evidence/01M4DK7C9KE09JXBG0DQVT0PRS
export FM_HERDR_LAB_STATE_DIR="$ROOT/.test-live/lab-state" TMPDIR="$ROOT/.test-live/tmp"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
helper="$ROOT/bin/fm-herdr-lab.sh"
session=$("$helper" name readiness-bound)
trap '"$helper" teardown "$session" >> "$E/adversary.log" 2>&1' EXIT
"$helper" provision "$session"
lab() { "$helper" run "$session" "$@"; }
. "$ROOT/bin/backends/herdr.sh"
fm_backend_herdr_cli() { local session=$1; shift; "$helper" run "$session" "$@"; }
mkdir -p "$ROOT/.test-live/fresh"
git init -q "$ROOT/.test-live/fresh"
pane=$(lab workspace create --cwd "$ROOT/.test-live/fresh" --label readiness-bound --no-focus | jq -er '.result.root_pane.pane_id')
target="$session:$pane"
lab pane run "$pane" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude --permission-mode auto --settings '{\"feedbackDrafts\":\"off\"}'" > /dev/null
trust=0
for ((i=0;i<30;i++)); do
 screen=$(lab pane read "$pane" --source visible)
 if [[ "$screen" == *'Yes, I trust this folder'* ]]; then
   st=$(lab agent get "$pane" | jq -r '.result.agent.agent_status')
   composer=$(fm_backend_herdr_composer_state "$target")
   lab pane read "$pane" --source visible --format ansi > "$E/trust.ansi"
   printf 'TRUST native=%s composer=%s; requires idle/done AND empty\n' "$st" "$composer"
   [[ "$composer" != empty ]]
   trust=1
   lab pane send-keys "$pane" down enter > /dev/null
   break
 fi
 sleep 1
done
[[ "$trust" == 1 ]] || { echo 'No fresh-folder trust prompt observed'; exit 2; }
ready=0
for ((i=0;i<45;i++)); do
 st=$(lab agent get "$pane" | jq -r '.result.agent.agent_status')
 composer=$(fm_backend_herdr_composer_state "$target")
 if [[ "$st" == idle || "$st" == done ]] && [[ "$composer" == empty ]]; then ready=1; break; fi
 sleep 1
done
[[ "$ready" == 1 ]]
printf 'READY after trust native=%s composer=%s\n' "$st" "$composer"
lab pane read "$pane" --source visible --format ansi > "$E/ready.ansi"
lab pane send-text "$pane" 'Count from 1 to 150, writing each number on its own line. Do not use tools.' > /dev/null
lab pane send-keys "$pane" enter > /dev/null
busy=0
for ((i=0;i<60;i++)); do
 st=$(lab agent get "$pane" | jq -r '.result.agent.agent_status')
 if [[ "$st" == working ]]; then
   composer=$(fm_backend_herdr_composer_state "$target")
   lab pane read "$pane" --source visible --format ansi > "$E/busy.ansi"
   printf 'BUSY native=%s composer=%s; readiness rejected by native-status gate\n' "$st" "$composer"
   busy=1; break
 fi
 sleep 0.3
done
[[ "$busy" == 1 ]]
