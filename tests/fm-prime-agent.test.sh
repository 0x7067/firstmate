#!/usr/bin/env bash
# Prime Agent harness identity regression tests.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-prime-agent)
trap 'rm -rf "$TMP_ROOT"' EXIT
FAKEBIN=$(fm_fakebin "$TMP_ROOT")
BASE_PATH=$PATH

cat > "$FAKEBIN/ps" <<'SH'
#!/usr/bin/env bash
set -u
field=
pid=
while [ $# -gt 0 ]; do
  case "$1" in
    -o) field=$2; shift 2 ;;
    -p) pid=$2; shift 2 ;;
    *) shift ;;
  esac
done
case "$field:$pid:${FM_TEST_PRIME_SHAPE:-exact}" in
  comm=:200:exact) printf '%s\n' '/opt/prime/bin/prime-agent' ;;
  comm=:200:node) printf '%s\n' '/opt/node/bin/node' ;;
  args=:200:node) printf '%s\n' '/opt/node/bin/node /opt/node/lib/node_modules/prime-agent/dist/cli.js' ;;
  comm=:200:decoy) printf '%s\n' '/opt/prime/bin/prime-agent-helper' ;;
  args=:200:decoy) printf '%s\n' 'prime-agent-helper' ;;
  comm=:*) printf '%s\n' bash ;;
  args=:*) printf '%s\n' bash ;;
  ppid=:200:*) printf '%s\n' 1 ;;
  ppid=:*) printf '%s\n' 200 ;;
  *) exit 1 ;;
esac
SH
chmod +x "$FAKEBIN/ps"

detect() {
  env -u CLAUDECODE -u GROK_AGENT PATH="$FAKEBIN:$BASE_PATH" \
    PI_CODING_AGENT=true FM_TEST_PRIME_SHAPE="$1" "$ROOT/bin/fm-harness.sh"
}

got=$(detect exact)
[ "$got" = prime-agent ] \
  || fail "exact prime-agent ancestry resolved '$got', expected prime-agent"

got=$(detect node)
[ "$got" = prime-agent ] \
  || fail "Prime's node package ancestry resolved '$got', expected prime-agent"

got=$(detect decoy)
[ "$got" = pi ] \
  || fail "prime-agent-helper decoy resolved '$got', expected shared-marker Pi fallback"

pass "Prime ancestry outranks its shared Pi marker without widening to similar names"
