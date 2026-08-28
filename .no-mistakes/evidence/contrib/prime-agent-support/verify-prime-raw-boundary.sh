#!/usr/bin/env bash
set -u

repo=/Users/pedro/.no-mistakes/worktrees/b764898e6d62/01M14JP8YRDCTRXPK9AXXGE6GY
cd "$repo"

# Load the behavioral test's isolated public-interface driver without running
# its test list.
source tests/lib.sh
source <(sed -n '13,171p' tests/fm-spawn-dispatch-profile.test.sh)
trap 'rm -rf "$TMP_ROOT"' EXIT

rec=$(make_spawn_case evidence-prime-boundary claude evidence-arch evidence-echo)
read_case_record "$rec"

printf 'CASE: launcher that can dispatch Prime\n'
printf 'COMMAND: fm-spawn evidence-arch <project> "/usr/bin/arch prime-agent --flag"\n'
set +e
out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" \
  evidence-arch "$PROJ_DIR" "/usr/bin/arch prime-agent --flag")
status=$?
set -e
printf 'EXIT: %s\n' "$status"
printf 'OUTPUT: %s\n' "$out"
printf 'METADATA_CREATED: %s\n' "$([ -e "$HOME_DIR/state/evidence-arch.meta" ] && printf yes || printf no)"
printf 'BACKEND_LAUNCH_SENT: %s\n' "$([ -s "$LAUNCH_LOG" ] && printf yes || printf no)"

printf '\nCASE: allowed protected system utility\n'
printf 'COMMAND: fm-spawn evidence-echo <project> "/bin/echo hello-from-firstmate"\n'
set +e
out=$(run_ship_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$LAUNCH_LOG" \
  evidence-echo "$PROJ_DIR" "/bin/echo hello-from-firstmate")
status=$?
set -e
printf 'EXIT: %s\n' "$status"
printf 'OUTPUT: %s\n' "$out"
printf 'METADATA_CREATED: %s\n' "$([ -e "$HOME_DIR/state/evidence-echo.meta" ] && printf yes || printf no)"
printf 'BACKEND_LAUNCH: '
sed -n '1p' "$LAUNCH_LOG"
