# Porting map: Claude Code ↔ Codex ↔ OpenCode

| Capability | Claude Code | Codex | OpenCode |
|---|---|---|---|
| Workflow entry points | Plugin skills `/harness:plan`, `review`, `commit`, `pr`, `worktree`(-`remove`) | Protocol files installed as custom prompts at `<codex-home>/prompts/*.md` (confirmed, Task 8 docs check, 2026-08-31) AND, since Agent Skills are supported, as `harness-<name>/SKILL.md` — but at `$HOME/.agents/skills/`, a sibling of `<codex-home>`, **not** `<codex-home>/skills/` as the brief's interface line assumed; `install.sh` derives it as `dirname(<codex-home>)/.agents/skills` so a sandboxed install stays inside its temp dir. Current docs mark custom prompts themselves deprecated in favor of skills, but the installer still ships prompts — the sandbox test pins `<codex-home>/prompts/*.md` | The same protocol files, unchanged, as commands `<config>/commands/harness-*.md` (`/harness-plan` …; `$ARGUMENTS` works) AND as skills `<config>/skills/harness-*/SKILL.md`. OpenCode also reads `~/.agents/skills`; on a name clash the `<config>` copy wins, so installing both ports never duplicates a skill (verified 2026-09-17, OpenCode 1.18.31) |
| Architect consultation | Subagents (16 generic + project-declared domain architects) | The `/plan` protocol walks the architect council sequentially in one context | **Real subagents, opt-in.** `install.sh --with-agents` converts the 16 generic agents with `convert-agents.mjs` (tools → permission, model dropped so a subagent inherits the session model — local or hosted — and example blocks dropped from descriptions, ~950 tokens for all 16). Never copy a Claude agent file: OpenCode refuses to start on its `tools`/`color` frontmatter. Without the flag, the protocol walks the council in one context as in Codex |
| Graph verification (`plan-graph`, `review --graph`) | Workflow scripts orchestrating investigator/refuter subagents | **Does not port.** No orchestration primitive. The `/review` protocol keeps the anchor discipline (quotes + commands) without fresh-context verifiers | **Does not port.** Subagents exist but nothing runs the workflow scripts, so the three graph agents are not converted. A second-pass review can go to the converted reviewer subagent, which does start from a fresh context |
| Project self-description | CLAUDE.md (gate, routing table, components, branch, worktree table) | AGENTS.md, same sections minus subagent routing | AGENTS.md (the same file Codex reads). With no AGENTS.md, OpenCode falls back to CLAUDE.md and its Claude-only routing — which is why `scaffold/init.sh` stamps both |
| Global config | `~/.claude/settings.json`, hooks, keybindings | `~/.codex/config.toml` (no hook/keybinding equivalent) | `<config>/AGENTS.md` — harness rules merged as a marked block, the user's own rules kept (with no global AGENTS.md, OpenCode falls back to `~/.claude/CLAUDE.md`). `opencode.json` is never modified; `opencode/opencode.suggested.json` holds a permission set to paste. No hook/keybinding equivalent installed |
| Frozen-rule enforcement | `check-frozen.sh` in the plugin | Not enforced; `FROZEN.md` principles are inlined as prose in the protocols | Not enforced; same protocols as Codex |
| Memory | Claude Code auto-memory | None — AGENTS.md carries only durable, hand-curated facts | None — same as Codex |

Rule of thumb: content ports, orchestration doesn't. Anything that depends
on two contexts not sharing history (philosophy §2) has no Codex equivalent
and is only approximated. OpenCode sits between the two: it has fresh-context
subagents, so single consultations and second-pass reviews port for real, but
nothing orchestrates a graph of them.

`<config>` is `${XDG_CONFIG_HOME:-$HOME/.config}/opencode`. Config loads once
at startup — restart OpenCode after installing.
