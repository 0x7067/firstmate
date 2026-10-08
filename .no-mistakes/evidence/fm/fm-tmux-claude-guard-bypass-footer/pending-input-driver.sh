#!/usr/bin/env bash
set -eu
EVIDENCE=/home/denguinho/.no-mistakes/evidence/01M4CHW5YHGMARGX7629WDRE4A
case " $* " in
  *' capture-pane '*)
    output=$(/usr/bin/tmux "$@")
    if [[ "$output" == *'auto mode on'* ]] && [ ! -e "$EVIDENCE/pending-injected" ]; then
      /usr/bin/tmux -L "$2" send-keys -t claude -l 'unsent captain draft'
      touch "$EVIDENCE/pending-injected"
      sleep 0.3
      output=$(/usr/bin/tmux "$@")
      printf '%s\n' "$output" > "$EVIDENCE/blocked-startup-screen.txt"
    fi
    printf '%s\n' "$output"
    ;;
  *) exec /usr/bin/tmux "$@" ;;
esac
