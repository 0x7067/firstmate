#!/usr/bin/env bash
# Behavior tests for fm-spawn.sh second positional handling: the missing-positional
# case under `set -u`, the repo-name case (looking the value up through the
# projects registry), and the usage text that names what the value actually is.
#
# These tests drive the real spawn path against a fixture home and assert on
# observable outcomes: the exit status, the spawned `cd` target, and the usage
# text that the script emits on failure. A test that passes when the guard is
# removed (or when the registry lookup is deleted) would not be coverage, so
# every assertion names the specific defect the fix is supposed to remove.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-positional-project)

# Build a minimal firstmate home: data/, projects/, state/, config/, a stub
# tmux, and the no-op tools the spawn path shells out to. The registry file
# carries one project so a name resolution has something to match.
make_home() {  # <name> [task-id...]
  local name=$1 case_dir home fakebin id
  shift
  case_dir="$TMP_ROOT/$name"
  home="$case_dir/home"
  fakebin=$(fm_fakebin "$case_dir")
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects"
  touch "$home/state/.last-watcher-beat"
  printf '%s\n' claude > "$home/config/crew-harness"
  printf '%s\n' "backend = \"markdown\"" > "$home/.tasks.toml"
  printf '%s\n' "path = \"data/backlog.md\"" >> "$home/.tasks.toml"
  printf '%s\n' "# Backlog" "" "## In flight" "" "## Queued" "" "## Done" \
    > "$home/data/backlog.md"
  printf '%s\n' \
    "- quota-axi [direct-PR +yolo] - quota-axi test fixture" \
    > "$home/data/projects.md"
  git -C "$home/projects" init -q -b main
  git -C "$home/projects" config user.email "test@example.com"
  git -C "$home/projects" config user.name "test"
  for id in "$@"; do
    mkdir -p "$home/data/$id"
    cat > "$home/data/$id/brief.md" <<EOF
# Task
## Captain's intent
Exercise positional-project handling for $id.

## Firstmate spec
Drive fm-spawn through the missing-positional and repo-name cases.

# Definition of done
Delivery contract: mode=no-mistakes
EOF
  done
  fm_fake_exit0 "$fakebin" treehouse
  printf '%s\n' "$case_dir"
}

# Run the real spawn with overrides that route every addressable path at the
# fixture home, with FM_SPAWN_NO_GUARD=1 so the suite owns the environment
# without touching the live watcher guard or state.
run_spawn() {
  local case_dir=$1
  shift
  local home="$case_dir/home"
  local fakebin="$case_dir/fakebin"
  FM_ROOT_OVERRIDE='' \
    FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" \
    FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" \
    FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 \
    PATH="$fakebin:$PATH" \
    "$SPAWN" "$@" 2>&1
}

# Missing second positional no longer crashes under `set -u` with the
# `POS[1]: unbound variable` defect; it falls back to the task's repo field
# in data/backlog.md, prints a clean usage message when that field is absent,
# and exits non-zero so the operator notices. A test that exits 1 with the
# crash text would be the pre-fix behavior the bug describes.
test_missing_second_positional_uses_backlog_repo() {
  local out status case_dir
  case_dir=$(make_home missing-positional has-no-repo-task)
  out=$(run_spawn "$case_dir" has-no-repo-task --mode no-mistakes --yolo off)
  status=$?
  [ "$status" -ne 0 ] || fail "missing second positional should not exit zero"
  case "$out" in
  *"POS\[1\]: unbound variable"*) fail "POS[1] under set -u still crashes the spawn: $out" ;;
  *'usage: fm-spawn.sh <task-id> <project-path>'*) pass "missing positional prints clean usage when backlog repo is empty" ;;
  *) fail "missing positional refused with unexpected output: $out" ;;
  esac
}

# A second positional that names a registered project must resolve through the
# projects registry to its absolute clone under $FM_HOME/projects and reach the
# brief-content check; the `cd quota-axi: No such file` defect would surface as
# a `cd: quota-axi` line, which the test refuses. A pre-fix invocation lands on
# that line; the test only passes when the registry lookup rewrites it.
test_repo_name_resolves_through_registry() {
  local out status case_dir expected
  case_dir=$(make_home repo-name quota-axi-task)
  mkdir -p "$case_dir/home/projects/quota-axi"
  git -C "$case_dir/home/projects/quota-axi" init -q
  out=$(run_spawn "$case_dir" quota-axi-task quota-axi --mode no-mistakes --yolo off)
  status=$?
  [ "$status" -ne 0 ] || fail "registry-named repo path should still fail the brief validation, not exit zero"
  case "$out" in
  *'cd: quota-axi'*) fail "repo name was not rewritten through the registry: $out" ;;
  *'has no backlog item in this home'*) pass "repo name resolved through registry and reached the backlog gate" ;;
  *) fail "registry-named repo path refused unexpectedly: $out" ;;
  esac
}

# The script advertises `<project-dir>` in its usage block, which invited the
# operator mistake of passing the home path as the project; the corrected text
# must say `<project-path>` and explain the supported forms, so neither the
# `cd quota-axi` operator trap nor the home-path mis-dispatch can recur from
# the usage line alone. The assertion is on the rendered `--help` output, not
# the source: removing the header change keeps the source bytes the same while
# this test stays green.
test_usage_text_describes_project_path() {
  local out
  out=$("$SPAWN" --help 2>&1) || fail "--help should exit zero"
  case "$out" in
  *'<project-path>'*) ;;
  *) fail "usage text still advertises <project-dir> instead of <project-path>: $out" ;;
  esac
  case "$out" in
  *"registered project name"*) ;;
  *) fail "usage text does not mention the registered-name form: $out" ;;
  esac
  case "$out" in
  *'projects/<name>'*) ;;
  *) fail "usage text does not mention the projects/<name> form: $out" ;;
  esac
  case "$out" in
  *'<project-dir>'*)
    fail "usage text still contains the misleading <project-dir> form: $out"
    ;;
  *) pass "usage text advertises <project-path> with the supported forms" ;;
  esac
}

test_missing_second_positional_uses_backlog_repo
test_repo_name_resolves_through_registry
test_usage_text_describes_project_path
