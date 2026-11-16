# agent-harness: design

**Status:** current as of plugin 0.4.0
**Audience:** engineers evaluating, adopting, or contributing to the harness

This document explains how the harness is built and why. The [field guide](guide.md)
covers which command to use. The [philosophy](philosophy.md) states the rules in short
form. The [plan-graph reference](plan-graph.md) documents every knob of one workflow.

## 1. Problem

Coding agents produce plausible work faster than a person can check it. Three failure
patterns show up again and again once a team uses an agent every day:

1. **Unanchored claims.** A plan says "the service already validates X" from memory of
   the code. The claim reads as fact and is wrong often enough to matter.
2. **Self-verification.** The agent that wrote a change also reviews it. A reviewer that
   saw the reasoning tends to agree with it, so the review adds cost and little signal.
3. **Configuration drift.** Each project copies a `.claude/` folder of skills and agents.
   The copies diverge, fixes land in one project and miss the rest, and nobody can say
   which version is current.

The harness is a reusable layer that addresses all three. It works on any codebase and
carries no knowledge of any particular one.

## 2. Goals and non-goals

**Goals**

- One engine of workflow skills and agents that installs once and updates by version.
- Every factual claim in a plan or review carries an anchor that a shell command can
  re-check.
- Verification runs in a fresh context that never sees the worker's reasoning.
- Failures are visible in the output. A partial result says it is partial.
- Rules that protect correctness cannot be weakened by an accidental edit.
- The same discipline is available in Codex and OpenCode, even where those tools lack
  the primitives to enforce it.

**Non-goals**

- Integrations with ticketing, deploy, or analytics systems. These wrap the engine from
  outside (see `addons/README.md`).
- Automatic retries or self-repair of failed agent runs.
- Porting graph orchestration to tools that have no orchestration primitive.

## 3. Architecture

```
                         ┌───────────────────────────────────────────┐
  this repo              │ plugins/harness/   (the engine)           │
  (also a plugin    ───► │   skills/     plan, plan-graph, review,   │ ──► installed by version
   marketplace)          │               commit, pr, worktree, ...   │     (claude plugin install)
                         │   agents/     19 generic agents           │
                         │   workflows/  plan-graph.js, review-graph │
                         │   scripts/    check-quote, risk-gate,     │
                         │               check-frozen                │
                         └───────────────────────────────────────────┘
                         ┌──────────────────────┐  ┌──────────────────────┐
                         │ scaffold/            │  │ global/              │
                         │ stamped once into a  │  │ merged into          │
                         │ project; the project │  │ ~/.claude: perms,    │
                         │ owns it afterwards   │  │ hooks, keybindings   │
                         └──────────────────────┘  └──────────────────────┘
                         ┌──────────────────────┐  ┌──────────────────────┐
                         │ codex/               │  │ opencode/            │
                         │ protocols as prompts │  │ commands, skills,    │
                         │ and skills           │  │ converted subagents  │
                         └──────────────────────┘  └──────────────────────┘
```

The engine reads project specifics at run time from the project's `CLAUDE.md` (or
`AGENTS.md` for the ports): components, check commands, protected branches, worktree
location, and the domain-to-architect routing table. The engine never stores them.

### 3.1 Workflows

**The loop** (`/harness:plan`, `/harness:review`) is the default. A skill gathers
context, consults specialist agents in prose, and produces a plan or a three-pass
review. It suits most changes.

**The graph** (`/harness:plan-graph`, `/harness:review --graph`) is a JavaScript
workflow run by Claude Code's Workflow tool. Coordination happens in code, so
intermediate findings never enter the session's context.

`plan-graph` runs this pipeline:

```
Lead ─► [validate] ─► Investigators (parallel) ─► [reduce] ─► Refuters (parallel) ─► Synthesizer ─► [post-pass]
```

- The lead partitions the question into 2 to 5 briefs and records what it chose not to
  cover.
- Cheap read-only investigators return findings. Each finding carries a verbatim quote
  at a file and line.
- Code deduplicates and ranks the findings, then caps how many get verified. Findings
  past the cap stay in the output with the label `past-cap`.
- Each refuter gets only the claim, file, line, and quote. It runs `check-quote.sh` and
  defaults to *refuted* when it cannot re-establish the claim.
- One strong agent designs the plan from confirmed findings only.
- Code checks the design for dependency cycles, edges to phases that do not exist, and
  edges that no shared file justifies. It also reconciles finding counts. Every finding
  ends as exactly one of confirmed, refuted, unverified, or past-cap.

`review-graph` runs five lenses (general, conventions, security, silent failure, tests)
in parallel. It then sends each finding to three skeptics that ask different questions:
is the claim correct, is the consequence reachable from a caller, and is it already
handled or outside the diff. A strict majority kills a finding.

## 4. Key decisions

Each decision lists the alternatives considered and the cost of the choice.

### D1. Ship the engine as a plugin; stamp the project layer once

The engine ships as a Claude Code plugin from this repo, which doubles as a plugin
marketplace. `scaffold/init.sh` stamps the project-owned files once.

- *Alternative:* a copy script that syncs `.claude/` into each project. This is the
  model that produced the drift in §1.
- *Cost:* a project cannot patch an engine skill in place. It wraps the skill with an
  unnamespaced skill of its own (`/plan` delegating to `/harness:plan`). That seam is
  documented and is also how add-ons work.

### D2. Separate worker and verifier contexts

A verifier never sees the worker's transcript. Refuters receive the claim and the
anchor only.

- *Alternative:* pass the worker's reasoning to the checker. This is cheaper, and the
  output looks the same.
- *Cost:* each verifier re-reads code the worker already read. The plan-graph reference
  measures plan-graph at roughly twice the tokens of `/harness:plan`.

### D3. A verbatim quote is the only admissible anchor

A finding in `plan-graph` is admissible only with a quote that `check-quote.sh` finds at
or near the claimed line. The script collapses whitespace and normalizes nothing else,
so a paraphrase fails.

- *Alternative:* accept file and line alone. A file and line feel precise, and nothing
  checks that the line says what the claim says.
- *Alternative:* run the test suite as evidence. The source project's suite was measured
  at about 30% flaky, which makes a test run evidence in both directions. Frozen rule F2
  forbids it.

### D4. Fail visibly, with no self-repair

There are no automatic retries. A missing investigator is named in the log and the run
is stamped `partial`. A refuter that crashes leaves its finding `unverified`, which is
neither confirmed nor refuted. Recovery uses `resumeFromRunId`, which replays completed
agent calls from cache and re-runs only the layer that died.

- *Alternative:* retry until every node returns. Retries hide infrastructure failures
  inside results that look complete, and they make cost unpredictable.
- *Cost:* the user sees more partial runs and has to decide whether to resume.

### D5. Freeze the rules an optimizer would bend

Some rules make a run cheaper or tidier when weakened. Examples are "silence is not
agreement", "default to refuted", and "findings are scoped to the diff". Each such rule
has a marker sentence, listed in `plugins/harness/FROZEN.md`, and `check-frozen.sh`
fails when a marker disappears. Rewording a rule means updating its marker on purpose in
the same commit.

- *Alternative:* rely on review to catch weakened rules. The project lost five rules
  this way when a refactor tidied `/harness:review`, and nobody noticed for weeks.

### D6. Structural risk gating, no keyword scoring

`risk-gate.sh` decides whether a diff deserves the graph. It matches file paths for a
mandatory tier and rejects only diffs that cannot carry a bug. It advises and never
blocks.

- *Alternative:* score changed lines for words like `state`, `role`, or `amount`. On a
  real 22-file React diff this reported no risk, and the graph then found three
  money-path bugs in it. The risk was structural. Frozen rule F3 keeps keyword scoring
  out.

### D7. The engine knows no project

Skills and agents carry method only. A CI check (`de-beeped` in `tests/run-all.sh`)
fails if names from the source project leak back into the engine. Another check fails
if an in-plugin agent is referred to by a bare name, because bare names only resolve
inside this repo and break for plugin consumers.

### D8. Ports carry content; orchestration stays in Claude Code

Codex gets the workflows as single-context protocols. OpenCode gets them as commands and
skills, plus optional real subagents converted by `opencode/convert-agents.mjs`. Neither
port runs the graph workflows, because neither tool has an orchestration primitive.
`docs/porting.md` records exactly what maps and what is lost.

## 5. Failure model

| Failure | Behavior |
|---|---|
| Lead returns nothing or one brief | Run ends early, `partial: true`, explicit error |
| Investigator returns nothing | Counted as missing; run continues as partial |
| Refuter crashes | Finding stays `unverified` |
| Whole verify layer dies | Findings preserved; log prints the resume instruction |
| Synthesizer returns nothing | Verified findings returned; plan empty; partial |
| Design has cycles or fake edges | Warned and surfaced; never auto-corrected |

## 6. Testing

`tests/run-all.sh` is the gate. CI runs it on every push and pull request, on Ubuntu
and macOS (`.github/workflows/ci.yml`). It checks:

- **Manifests and syntax.** Plugin and marketplace JSON parse. Every shell script passes
  `bash -n`. The OpenCode converter passes `node --check`.
- **Workflow behavior.** `plan-graph.smoke.mjs` and `review-graph.smoke.mjs` run the
  real workflow scripts against stubbed agents. They cover validation, reduce, the
  verify outcomes, the fake-edge post-pass, and early exits.
- **Frozen rules.** `check-frozen.sh` confirms every marker is present.
- **Hygiene.** Agent names are qualified, and no source-project names leak into the
  engine.
- **Installers.** The global, scaffold, Codex, and OpenCode installers run in a sandbox
  `HOME` built with `mktemp`. The tests assert idempotency, that existing user files
  survive, that backups are written, and that the real home directory is untouched.

The smoke tests prove the coordination code. They cannot prove model behavior. Model
behavior is measured in live runs and recorded next to the rule it justifies (see
`FROZEN.md` and the review skill).

## 7. Cost

| Workflow | Agent calls | Relative cost |
|---|---|---|
| `/harness:plan` | specialists in one session | baseline |
| `/harness:plan-graph` | 1 lead + briefs + verified findings × votes + 1 synthesizer, about 10 to 30 | about 2× `/harness:plan` |
| `/harness:review` | three passes | baseline |
| `/harness:review --graph` | 5 lenses + capped findings × 3 skeptics + 1 synthesizer | about 10× the loop |

The review skill lists five cases where the graph is the wrong tool. Frozen rule F6
protects that list from being trimmed.

## 8. Limitations and open questions

- **Measurement is thin.** The cost and refutation figures come from a small number of
  live runs on one production codebase. A replayable evaluation set would turn them into
  regression checks.
- **The global hooks are macOS only.** They use AppleScript. Linux users take the
  engine-only install path.
- **Two graph lenses depend on another plugin** (`pr-review-toolkit`). Without it those
  lenses skip and the review is marked partial.
- **Skeptic value is unproven at the loop tier.** On the first live graph run nine
  skeptics refuted none of three findings. Skeptics stay in the graph path only, and the
  decision is up for review once more runs exist.
- **A shared state format is in progress.** Open work defines one GraphState schema so
  plan and review runs can hand results to each other and be resumed or audited from a
  file.
