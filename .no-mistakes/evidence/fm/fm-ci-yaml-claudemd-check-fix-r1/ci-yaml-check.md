# CI CLAUDE.md-pointer check fix - test evidence

## 1. Reproduce malformed YAML (bug) vs valid YAML (fix)
Parsed both ci.yml revisions with a real YAML parser (Ruby Psych).

BASE (4913723, before fix):
  PARSE: FAILED
  ERROR: Psych::SyntaxError: could not find expected ':' while scanning a simple key at line 381 column 1
  -> the column-0 heredoc body (`@AGENTS.md`, `EOF`) terminates the `run: |`
     block scalar and breaks the workflow; it parses as zero jobs.

TARGET (b62f5f9, after fix):
  PARSE: OK
  JOBS: 9 -> lint, test-coverage, tests-portable-parallel-1, tests-portable-parallel-2,
             tests-portable-serial, tests-herdr, tests-timing-aggregate,
             macos-stock-bash, invariants

## 2. Behavior of the fixed check (extracted the real step body from parsed YAML, executed under bash)
  [canonical_ok]     exit=0  (correct pointer + correct skills symlink -> pass)
  [claudemd_symlink] exit=1  ::error::CLAUDE.md must be a real @AGENTS.md pointer file, not a symlink
  [wrong_bytes]      exit=1  ::error::CLAUDE.md must be the canonical @AGENTS.md pointer
  [wrong_pointer]    exit=1  ::error::CLAUDE.md must be the canonical @AGENTS.md pointer  (@CLAUDE.md rejected)
  [skills_broken]    exit=1  ::error::.claude/skills must be a symlink to ../.agents/skills

## 3. Real repo
  - extracted check runs clean (exit 0) against the actual worktree files
  - CLAUDE.md tracked mode 100644 (regular file), .claude/skills mode 120000 (symlink)
  - CLAUDE.md bytes exactly:
      <!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->\n@AGENTS.md\n
