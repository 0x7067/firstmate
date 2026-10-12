Race-only live validation

The race driver copies the unchanged target bin/ product into a disposable code root inside the gate worktree. This lets sibling disposable secondmate homes satisfy the product's prohibition on homes nested inside its code root. The product, tmux, and Codex CLI are real; no executable is mocked in this driver. Four recovery processes call the shared probe/relaunch interface concurrently, as the bootstrap sweep does. Each receives a private home and a real 120x40 tmux endpoint. All four spawns succeed and subsequent product probes report alive. The attempt/outcome ledger intervals show serialization.

Commands: bash .nm-live-race.sh base; bash .nm-live-race.sh; bash .nm-live-locks.sh.

The base variant substitutes only the base commit's fm-secondmate-liveness-lib.sh into the disposable target code copy. With identical setup, three spawns refuse because another spawn owns the task-set lock. This is a controlled regression comparison, not a full-base-checkout test.

Codex reaches folder-trust prompts. They were left unanswered to avoid changing user-level configuration. These checks prove process launch, metadata publication, lock serialization, and subsequent liveness classification; they do not prove model-task readiness. No remote SSH transport or Herdr session was used. The separate Claude exit-send defect is excluded by decision A and was not validated.

An initial private-tmux setup inherited the user's shell line editor, which retained the launch text in a multiline buffer. The final driver sets default-command to bash --noprofile --norc on the private lab server. The final target transcript proves all four endpoints run codex. This was an isolated setup correction.

The lock driver executes the actual fm-spawn.sh against disposable task-set lock state for task-spawn, forced-teardown, and unknown holder roles. Each refuses with the appropriate description and leaves no task metadata. Its bounded-wait scenario holds the actual per-home relaunch lock while the real product classifies a real shell endpoint dead. Recovery waits one second, skips without an attempt ledger, and preserves that endpoint.

Targeted automated checks also passed: bash tests/fm-secondmate-liveness.test.sh and five selected task-set safety cases from tests/fm-secondmate-safety.test.sh. Those use mocked backend fixtures and are not counted as live proof. No full suite, lint, static analysis, publishing, or pipeline-control command was run.

All disposable worktree homes, copied code, and private tmux servers were removed. The short socket directory allocated by fm-lab-home.sh tmux-dir was removed through its teardown helper.
