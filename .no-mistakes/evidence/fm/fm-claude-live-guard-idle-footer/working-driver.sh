#!/usr/bin/env bash
set -u
ROOT=$PWD
export FM_HERDR_LAB_STATE_DIR="$ROOT/.live-test-tmp/lab-state"
S=$(bin/fm-herdr-lab.sh name idle-boundary)
lab() { "$ROOT/bin/fm-herdr-lab.sh" run "$S" "$@"; }
cleanup() { "$ROOT/bin/fm-herdr-lab.sh" teardown "$S"; }
trap cleanup EXIT
bin/fm-herdr-lab.sh provision "$S" || exit 1
bin/fm-herdr-lab.sh viewer start "$S" || exit 1
P=$(lab workspace create --cwd "$ROOT" --label working-boundary --no-focus | jq -r '.result.root_pane.pane_id')
herdr() { local -a a=("$@"); local n=${#a[@]}; [ "${a[n-1]}" = "$S" ] || return 98; lab "${a[@]:0:n-2}"; }
. bin/backends/herdr.sh
lab pane run "$P" "env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME=$ROOT/.live-test-tmp/home CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude --permission-mode auto --settings '{\"disableAllHooks\":true}'" >/dev/null
ready=0
for i in {1..45}; do
 st=$(lab agent get "$P" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
 c=$(fm_backend_herdr_composer_state "$S:$P")
 case "$st:$c" in idle:empty|done:empty) ready=1; break;; esac
 sleep 1
done
[ "$ready" = 1 ] || { echo 'SETUP: no idle composer'; exit 1; }
lab pane send-text "$P" 'Think carefully about how to calculate the first 100 primes, then reply with the first ten primes only.' >/dev/null
lab pane send-keys "$P" enter >/dev/null
for i in {1..60}; do
 st=$(lab agent get "$P" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
 c=$(fm_backend_herdr_composer_state "$S:$P")
 if [ "$st" = working ]; then
   lab pane read "$P" --source visible
   printf 'Active turn native=%s composer=%s; ready=false\n' "$st" "$c"
   echo 'PASS: native working does not pass idle-plus-empty readiness'
   exit 0
 fi
 sleep 0.2
done
echo 'No working interval observed'; exit 1
