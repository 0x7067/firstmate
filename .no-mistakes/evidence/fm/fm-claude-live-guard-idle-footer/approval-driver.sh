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
mkdir -p "$ROOT/.live-test-tmp/untrusted"
P=$(lab workspace create --cwd "$ROOT/.live-test-tmp/untrusted" --label idle-boundary --no-focus | jq -r '.result.root_pane.pane_id')
herdr() { local -a a=("$@"); local n=${#a[@]}; [ "${a[n-1]}" = "$S" ] || return 98; lab "${a[@]:0:n-2}"; }
. bin/backends/herdr.sh
lab pane run "$P" "env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME=$ROOT/.live-test-tmp/home claude --permission-mode auto" >/dev/null
for i in {1..25}; do
 screen=$(lab pane read "$P" --source visible)
 case "$screen" in *'Yes, I trust this folder'*|*'Allow external CLAUDE.md file imports?'*) break;; esac
 sleep 1
done
printf '%s\n' "$screen"
st=$(lab agent get "$P" | jq -r '.result.agent.agent_status')
c=$(fm_backend_herdr_composer_state "$S:$P")
printf 'Trust prompt native=%s composer=%s\n' "$st" "$c"
[ "$c" != empty ] || exit 1
case "$screen" in *'Yes, I trust this folder'*|*'Allow external CLAUDE.md file imports?'*) ;; *) exit 1;; esac
printf 'PASS: unresolved trust or import approval dialog cannot meet idle-plus-empty readiness\n'
