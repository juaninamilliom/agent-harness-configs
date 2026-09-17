# Harness working agreement

## Discipline
- Read the code first. Every load-bearing claim carries file:line and a
  verbatim quote you re-checked with a command this session.
- Non-trivial work: run the plan protocol (`/harness-plan`, or the
  `harness-plan` skill) before editing. Bug reports and questions get
  findings, not unrequested fixes.
- Before any commit: run the commit protocol (`/harness-commit`). Type check
  hard-blocks; review criticals block.
- Type-check, never build, during development (`npx tsc --noEmit` or the
  project AGENTS.md equivalent). Don't trust a test suite the project
  hasn't declared trustworthy.
- Self-review in a second pass. If the harness subagents are installed,
  hand the diff to the reviewer subagent: it starts from a fresh context and
  has not seen your reasoning. Otherwise re-read your diff as if someone else
  wrote it, hunting the claim you didn't verify.

## Communication
- Plainspoken; lead with the outcome; no flattery.
- Report failures verbatim; never claim verified when you haven't run it.
