set -eu
. .live-pi/base-composer.sh
fail() { echo "FAIL: $*"; exit 1; }
pass() { echo "PASS: $*"; }
ESC=$(printf '\033')
NBSP=$(printf '\302\240')
CAPS_TMUX=$'styled=1\ncursor=1\nidentity=1\nrows=0'
CAPS_STYLED=$'styled=1\ncursor=0\nidentity=1\nrows=20'      # herdr
CAPS_STYLED_NOID=$'styled=1\ncursor=0\nidentity=0\nrows=20' # zellij
CAPS_PLAIN=$'styled=0\ncursor=0\nidentity=0\nrows=20'       # cmux, orca

# assert_screen <label> <want> <caps> <screen> [cursor] [identity]: one
# verdict, asserted under the ambient locale AND LC_ALL=C.
assert_screen() {
  local label=$1 want=$2 out
  shift 2
  out=$(fm_composer_classify_screen "$@")
  [ "$out" = "$want" ] || fail "$label: expected $want, got '$out'"
  out=$(LC_ALL=C fm_composer_classify_screen "$@")
  [ "$out" = "$want" ] || fail "$label under LC_ALL=C: expected $want, got '$out'"
}

test_matrix_pi_104_titled_top_border() {
  local screen typed malformed top bottom top_inner bottom_inner top_fill bottom_fill content draft tail width effort
  local family left_top right_top left_bottom right_bottom dash side rule
  top_inner='─ ⎇ detached ─'
  width=${top_inner//─/ }
  width=${width//⎇/ }
  printf -v top_fill '%*s' "$((70 - ${#width}))" ''
  top="╭${top_inner}${top_fill// /─}╮"
  printf -v content '%*s' 69 ''
  draft='❯ fix the composer proof'
  width=${draft//❯/>}
  printf -v tail '%*s' "$((70 - ${#width}))" ''
  for effort in low medium high xhigh max; do
    bottom_inner="─ 0.0s · pi-codex · $effort ─"
    width=${bottom_inner//─/ }
    width=${width//·/ }
    printf -v bottom_fill '%*s' "$((70 - ${#width}))" ''
    bottom="╰${bottom_inner}${bottom_fill// /─}╯"
    screen="$top"$'\n│❯'"$content"$'│\n'"$bottom"
    assert_screen "Pi 1.0.4 detached branch frame ($effort) on Herdr" empty "$CAPS_STYLED" "$screen"
    assert_screen "Pi 1.0.4 detached branch frame ($effort) with cursor" empty "$CAPS_TMUX" "$screen" 1
    typed="$top"$'\n│'"$draft$tail"$'│\n'"$bottom"
    assert_screen "Pi 1.0.4 typed branch frame ($effort) on Herdr" pending "$CAPS_STYLED" "$typed"
    assert_screen "Pi 1.0.4 typed branch frame ($effort) with cursor" pending "$CAPS_TMUX" "$typed" 1
  done
  top_inner='─ ⎇ bad branch ─'
  width=${top_inner//─/ }
  width=${width//⎇/ }
  printf -v top_fill '%*s' "$((70 - ${#width}))" ''
  malformed="╭${top_inner}${top_fill// /─}╮"$'\n│❯'"$content"$'│\n'"$bottom"
  assert_screen "Pi 1.0.4 malformed branch title stays unknown" unknown "$CAPS_STYLED" "$malformed"
  top_inner='─ ⎇ feature/composer-proof ─'
  width=${top_inner//─/ }
  width=${width//⎇/ }
  printf -v top_fill '%*s' "$((70 - ${#width}))" ''
  top="╭${top_inner}${top_fill// /─}╮"
  screen="$top"$'\n│❯'"$content"$'│\n'"$bottom"
  assert_screen "Pi 1.0.4 named branch frame on Herdr" empty "$CAPS_STYLED" "$screen"
  printf -v rule '%*s' 70 ''
  for family in light double heavy ascii; do
    case "$family" in
      light) left_top='┌'; right_top='┐'; left_bottom='└'; right_bottom='┘'; dash='─'; side='│' ;;
      double) left_top='╔'; right_top='╗'; left_bottom='╚'; right_bottom='╝'; dash='═'; side='║' ;;
      heavy) left_top='┏'; right_top='┓'; left_bottom='┗'; right_bottom='┛'; dash='━'; side='┃' ;;
      ascii) left_top='+'; right_top='+'; left_bottom='+'; right_bottom='+'; dash='-'; side='|' ;;
    esac
    top="$left_top${top_inner//─/$dash}${top_fill// /$dash}$right_top"
    bottom="$left_bottom${rule// /$dash}$right_bottom"
    screen="$top"$'\n'"${side}❯${content}${side}"$'\n'"$bottom"
    assert_screen "Pi-shaped titled top in $family frame stays unknown" unknown "$CAPS_STYLED" "$screen"
    top="$left_top${rule// /$dash}$right_top"
    bottom="$left_bottom${bottom_inner//─/$dash}${bottom_fill// /$dash}$right_bottom"
    screen="$top"$'\n'"${side}❯${content}${side}"$'\n'"$bottom"
    assert_screen "Pi-shaped footer in $family frame stays unknown" unknown "$CAPS_STYLED" "$screen"
  done
  pass "matrix: Pi 1.0.4 branch-titled frames prove empty and pending composers while malformed titles stay unknown"
}


test_matrix_pi_104_titled_top_border
