#!/bin/bash
set -eu
ROOT=$PWD
E=/Users/pedro/.no-mistakes/evidence/01M3SDPW8TREH6V2S6Y8EVAZ4V
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
cleanup() { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null || true; chmod -R u+w "$LAB"; rm -r "$LAB"; }
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB"
mkdir -p "$LAB/tmux" "$ROOT/.test-codex-live/user" "$ROOT/.test-codex-live/project"
export HOME="$ROOT/.test-codex-live/user" CODEX_HOME="$ROOT/.test-codex-live" TREEHOUSE_ROOT="$ROOT/.test-codex-live/pool" SHELL=/bin/bash
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export FM_HOME="$LAB" TMUX_TMPDIR="$LAB/tmux"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE FM_GATE_REFUSE_BYPASS
P="$ROOT/.test-codex-live/project"
git -C "$P" init -q -b main
git -C "$P" -c user.name=Test -c user.email=test@example.invalid commit -qm 'test: seed' --allow-empty
tmux -L fm-lab new-session -d -s primary -x 120 -y 40 -c "$ROOT" /bin/bash
export TMUX=$(tmux -L fm-lab display-message -p -t primary '#{socket_path}'),1,0
for entry in default-max:default default-clamp:default env-kept:default env-dropped:default profile:default; do
 id=${entry%%:*}; model=${entry#*:}
 export HOME="$ROOT/.test-codex-live/cases/$id/user" CODEX_HOME="$ROOT/.test-codex-live/cases/$id/codex"
 mkdir -p "$CODEX_HOME" "$HOME"
 tmux -L fm-lab set-environment -t primary HOME "$HOME"
 tmux -L fm-lab set-environment -t primary CODEX_HOME "$CODEX_HOME"
 touch "$LAB/state/.last-watcher-beat"
 mkdir -p "$HOME/.codex" "$LAB/data/$id"
 printf 'model = "gpt-5.6-luna"\n' > "$CODEX_HOME/config.toml"
 printf 'model = "gpt-5.5"\n' > "$HOME/.codex/config.toml"
 [ ! -f "$LAB/config/launch-env-allowlist" ] || rm "$LAB/config/launch-env-allowlist"
 case "$id" in
 default-clamp) printf 'model = "gpt-5.5"\n' > "$CODEX_HOME/config.toml" ;;
 env-kept) printf 'CODEX_HOME\n' > "$LAB/config/launch-env-allowlist" ;;
 env-dropped) : > "$LAB/config/launch-env-allowlist" ;;
 profile) printf 'model = "gpt-5.6-luna"\nprofile = "work"\n[profiles.work]\nmodel = "gpt-5.5"\n' > "$CODEX_HOME/config.toml" ;;
 esac
 printf '# Task\n## Captain\047s intent\nReply OK only, do not run any tools.\n## Firstmate spec\nReply OK only.\n' > "$LAB/data/$id/brief.md"
 bin/fm-spawn.sh "$id" "$P" --scout --harness codex --model "$model" --effort max > "$E/live-$id.log" 2>&1 || { cat "$E/live-$id.log"; exit 1; }
 sleep 3
 ps -axo command= | awk -v needle="state/$id.turn-ended" 'index($0,needle) && $1 ~ /codex$/ {print}' > "$E/live-$id-process.txt"
 tmux -L fm-lab list-panes -a -F '#{pane_id} #{pane_current_command} #{pane_current_path}' >> "$E/live-$id.log"
 tmux -L fm-lab capture-pane -p -S -200 -t "fm-$id" >> "$E/live-$id.log" || true
 /usr/bin/python3 - "$E/live-$id.log" "$E/live-$id-launch.txt" <<'PY2'
import re,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text().replace('\n','')
m=re.search(r"\. '(/tmp/fm-[^']+/launch\.[^']+\.sh)'",text)
if m: Path(sys.argv[2]).write_text(Path(m[1]).read_text())
PY2
 /usr/bin/python3 - "$id" "$LAB" "$E" <<'PY3'
import subprocess,sys,re,json
from pathlib import Path
id,lab,e=sys.argv[1:]
rows=subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines()
found=[]
for row in rows:
 pid,cmd=row.strip().split(None,1)
 if cmd.split()[0].endswith('codex') and f'state/{id}.turn-ended' in cmd and Path(lab).name in cmd:
  envtext=subprocess.check_output(['ps','eww','-p',pid,'-o','command='],text=True)
  found.append({'pid':pid,'HOME':re.findall(r'(?:^| )HOME=([^ ]*)',envtext),'CODEX_HOME':re.findall(r'(?:^| )CODEX_HOME=([^ ]*)',envtext)})
Path(e,f'live-{id}-environment.json').write_text(json.dumps(found,indent=2))
PY3
 cp "$LAB/state/$id.meta" "$E/live-$id.meta"
done
