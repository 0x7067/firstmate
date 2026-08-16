# /stow record safety-net - targeted validation

## Consumer tests (real consumers of the changed files)

```
$ bash tests/fm-documentation-audiences.test.sh
ok - documentation inventory classifies every maintained prose surface exactly once
ok - classification, setup routing, and maintained-prose scope fail safely
ok - required documentation owner pointers cannot silently disappear
ok - local links resolve while dates, versions, commands, and incident prose remain semantically reviewed
exit=0

$ bash tests/fm-stow-cascade.test.sh
ok - each home is accounted against its own allowance instead of a fleet total
ok - the cascade emits one stanza per registered home and refuses a double-counted registry
ok - transport follows placement and live-agent state, and a remote home without an agent defers
ok - each stanza carries the facts a per-home receipt needs, before and after curation
ok - one slow or unreachable home is bounded and every other home still reports
ok - the cascade stays silent with no secondmates and never runs from a secondmate home
exit=0

$ bash tests/fm-supervision-instructions.test.sh   # changed skill = watched instruction surface
ok - renderer falls back to unknown.md for unverified harness names
ok - renderer includes read-only, afk, and effective x-mode current-state stanzas
ok - renderer repair-line mode is harness-aware and honors conditional state
ok - renderer preserves every harness ordinary-continuation and missing-cycle repair path
ok - pi-signed keeps its identity while sharing Pi's supervision protocol
ok - grok supervision is Claude-shaped background notify with passive Stop-hook backstop
ok - grok rendered command sources the effective x-mode config
ok - pi supervision snippet renders the effective extension path
exit=
```
