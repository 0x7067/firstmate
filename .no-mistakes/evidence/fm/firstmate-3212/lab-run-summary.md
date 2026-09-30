# Live lab validation - codex max CODEX_HOME pin (fm/firstmate-3212 @ 8e520e3a)

Fixture: marked disposable lab home (bin/fm-lab-home.sh create), private tmux
server `fm-lab` with session `firstmate`, project repo `$LAB/projects/notes`
with a local bare origin, real `treehouse` pool under $LAB/treehouse, real
codex-cli 0.159.2 intercepted by a PATH shim that logged each call's resolved
CODEX_HOME + argv before exec'ing the real binary. Pane ambient env:
CODEX_HOME=$LAB/decoy-codex (config.toml model=gpt-5.5, xhigh-only). fm-spawn
env: CODEX_HOME=$LAB/probed-codex (config.toml model=gpt-6.1-sol, max-capable).

## Runs
- labcodex-max-a   : `--effort max` (no --model). Probe: CODEX_HOME=probed ->
                     pass-through. Worker launch: CODEX_HOME=probed (PINNED)
                     despite pane ambient decoy. Real codex TUI started in pane.
- labcodex-clamp-b : `--model gpt-5.5 --effort max`. Probe -> clamp notice
                     "catalog does not advertise max for model 'gpt-5.5'";
                     launch emits model_reasoning_effort="xhigh", NO
                     CODEX_HOME pin; worker shim logged CODEX_HOME=decoy
                     (pane's own env), as intended for clamped launches.
- labcodex-env-c   : config/launch-env-allowlist ENABLED without CODEX_HOME.
                     Probe resolved $HOME/.codex ($LAB/spawn-home/.codex, the
                     home the env -i worker can actually see) -> pass-through;
                     pin CODEX_HOME='$LAB/spawn-home/.codex' embedded INSIDE the
                     /bin/sh -c payload, survived env -i; worker shim logged it.
- labcodex-prefix-d: PRE-FIX reproduction. Same lab, fm-spawn.sh extracted from
                     d603cc75 (HEAD~1). Probe confirmed max against
                     probed-codex, but the launch carried NO CODEX_HOME pin and
                     the worker shim logged CODEX_HOME=decoy-codex - i.e. the
                     daemon pane resolved a different default model (gpt-5.5,
                     xhigh-only) than the one max was confirmed against. This is
                     the reported Greptile P1 failure mode.
- labcodex-env-e   : allowlist WITH CODEX_HOME. Probe -> probed-codex; pin
                     embedded probed-codex inside env -i payload; worker shim
                     logged CODEX_HOME=probed-codex.
- labcodex-high-f  : `--effort high` control. Launch emits
                     model_reasoning_effort="high", no pin; worker shim logged
                     CODEX_HOME=decoy-codex (ambient pane env).

## Key files
- codex-calls-trimmed.log : every codex invocation with its resolved CODEX_HOME
- codex-calls-full.log    : same, untruncated (launch argv carries full brief)
- launch-<id>.sh          : the exact staged launch file each pane sourced
- pane-max-a.txt / pane-clamp-b.txt : real codex TUI running in worker panes
- meta-max-a.txt          : task record (harness=codex model=default effort=max)
- lab-windows.txt         : worker windows on the lab tmux server
