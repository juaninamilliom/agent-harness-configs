#!/bin/bash
# Install the harness OpenCode port into an OpenCode config dir
# (default ${XDG_CONFIG_HOME:-$HOME/.config}/opencode).
#
# Docs check (verified 2026-09-17 against opencode.ai/docs and OpenCode
# 1.18.31 run in a sandboxed HOME/XDG_CONFIG_HOME):
#   (a) Commands: <config>/commands/*.md, invoked as /<filename>. Frontmatter
#       `description:`; unknown keys (the protocols' `argument-hint:`) are
#       accepted. Body placeholders $ARGUMENTS and $1..$n work, so the Codex
#       protocols install unchanged. Source: opencode.ai/docs/commands.
#   (b) Skills: <config>/skills/<name>/SKILL.md, frontmatter `name:` (must
#       match the directory, ^[a-z0-9]+(-[a-z0-9]+)*$) + `description:`.
#       OpenCode ALSO reads ~/.agents/skills (where codex/install.sh puts the
#       same harness-* skills); on a name clash the <config>/skills copy wins,
#       so installing both ports never duplicates a skill. Only name and
#       description sit in the prompt; the body loads on demand.
#       Source: opencode.ai/docs/skills.
#   (c) Rules: <config>/AGENTS.md is the global rules file. When it is absent
#       OpenCode falls back to ~/.claude/CLAUDE.md, so writing it also stops a
#       Claude-specific file leaking into OpenCode sessions.
#       Source: opencode.ai/docs/rules.
#   (d) Agents: <config>/agents/*.md. OpenCode validates agent frontmatter
#       strictly and REFUSES TO START on a Claude Code agent file (`tools` must
#       be an object, `color` a hex or theme name), so agents are converted by
#       convert-agents.mjs, never copied. Source: opencode.ai/docs/agents.
#   (e) opencode.json is never modified - review opencode/opencode.suggested.json
#       and paste what you want. Config loads once at startup: restart OpenCode
#       after installing.
#
# Usage: install.sh [--with-agents] [opencode-config-dir]
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WITH_AGENTS=0
if [ "${1:-}" = "--with-agents" ]; then WITH_AGENTS=1; shift; fi
TARGET="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
mkdir -p "$TARGET/commands" "$TARGET/skills"

strip_frontmatter() { # prints a file's body after its closing --- line
  awk 'BEGIN{n=0} /^---$/{n++; next} n<2{next} {print}' "$1"
}

# (a) protocols as commands, namespaced so they never shadow a user's own /plan
for p in "$REPO"/codex/protocols/*.md; do
  cp "$p" "$TARGET/commands/harness-$(basename "$p")"
done
echo "commands installed: $(ls "$REPO"/codex/protocols/*.md | wc -l | tr -d ' ') (/harness-plan, /harness-review, ...)"

# (b) the same protocols as skills
skills_installed=0
for p in "$REPO"/codex/protocols/*.md; do
  name="harness-$(basename "$p" .md)"
  desc="$(sed -n 's/^description: *//p' "$p" | head -1)"
  mkdir -p "$TARGET/skills/$name"
  {
    echo "---"
    echo "name: $name"
    echo "description: $desc"
    echo "---"
    strip_frontmatter "$p"
  } > "$TARGET/skills/$name/SKILL.md"
  skills_installed=$((skills_installed + 1))
done
echo "skills installed: $skills_installed (at $TARGET/skills)"

# (c) global rules: a marked block inside AGENTS.md. The user's own rules are
# kept; a re-run replaces only the block.
BEGIN_MARK='<!-- agent-harness-configs:begin (managed by opencode/install.sh - edits inside are overwritten) -->'
END_MARK='<!-- agent-harness-configs:end -->'
BLOCK="$(mktemp)"; trap 'rm -f "$BLOCK"' EXIT
{ echo "$BEGIN_MARK"; cat "$REPO/opencode/AGENTS.global.md"; echo "$END_MARK"; } > "$BLOCK"
RULES="$TARGET/AGENTS.md"
if [ ! -s "$RULES" ]; then
  cp "$BLOCK" "$RULES"
  echo "AGENTS.md installed"
else
  cp "$RULES" "$RULES.bak"
  if grep -qF "$BEGIN_MARK" "$RULES"; then
    tmp="$(mktemp)"
    awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v blockfile="$BLOCK" '
      $0 == begin { while ((getline line < blockfile) > 0) print line; skip = 1; next }
      skip && $0 == end { skip = 0; next }
      !skip { print }' "$RULES" > "$tmp"
    mv "$tmp" "$RULES"
    echo "AGENTS.md harness block updated (your rules kept; backup at AGENTS.md.bak)"
  else
    { echo ""; cat "$BLOCK"; } >> "$RULES"
    echo "AGENTS.md harness block appended (your rules kept; backup at AGENTS.md.bak)"
  fi
fi

# (d) optional: generic architects as OpenCode subagents
if [ "$WITH_AGENTS" = 1 ]; then
  command -v node >/dev/null || { echo "--with-agents needs node" >&2; exit 1; }
  node "$REPO/opencode/convert-agents.mjs" "$REPO/plugins/harness/agents" "$TARGET/agents"
else
  echo "agents not installed (re-run with --with-agents; each one adds its description to every prompt)"
fi

echo ""
echo "opencode.json is never modified - review opencode/opencode.suggested.json and paste what you want"
echo "restart OpenCode to load the changes"
