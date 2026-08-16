# /stow open-record safety-net - test evidence

## 1. Behavioral tests (real consumers of the changed docs)

### tests/fm-documentation-audiences.test.sh
```
ok - documentation inventory classifies every maintained prose surface exactly once
ok - classification, setup routing, and maintained-prose scope fail safely
ok - required documentation owner pointers cannot silently disappear
ok - local links resolve while dates, versions, commands, and incident prose remain semantically reviewed
exit=0
```

### tests/fm-stow-cascade.test.sh
```
ok - each home is accounted against its own allowance instead of a fleet total
ok - the cascade emits one stanza per registered home and refuses a double-counted registry
ok - transport follows placement and live-agent state, and a remote home without an agent defers
ok - each stanza carries the facts a per-home receipt needs, before and after curation
ok - one slow or unreachable home is bounded and every other home still reports
ok - the cascade stays silent with no secondmates and never runs from a secondmate home
exit=0
```

## 2. Every command the new guidance instructs the agent to run is real and behaves as documented
```
$ bin/fm-decision-hold.sh id task-1234 deploy-target
task-1234-decision-deploy-target

$ tasks-axi show --help
usage: tasks-axi show <id> [--full]
aliases: view
examples:
  tasks-axi show homemux-h7

# backend paths referenced by the section:
tasks-axi add ... present
tasks-axi update ... present
tasks-axi show ... present
```

## 3. Rationale line is grounded in source (bin/fm-session-start.sh)
The 'wrong state' bullet claims the session-start digest reads identity fields, never body:
```
# `tasks-axi list` for the compact identity fields plus blocked_by, hold_kind,
# and hold_reason, never body. The groups are the tool's own filters
# (`--state in_flight`, `--state held`, `--state queued --blocked`, and
```

The hold-read path the review commit corrected reads the hold via tasks-axi (bin/fm-decision-hold.sh:165):
```
task_show() {  # <id>
  tasks_axi show "$1" --full 2>/dev/null
}
```
