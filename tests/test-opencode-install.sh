#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SB=$(mktemp -d); trap 'rm -rf "$SB"' EXIT
fail=0; chk() { if eval "$2"; then echo "  ok  $1"; else echo "  FAIL $1"; fail=1; fi; }

# Containment baseline: the real OpenCode config dir must be unaffected by a sandboxed install.
real_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
real_before=$(ls -laR "$real_cfg" 2>/dev/null | grep -v node_modules | md5 -q 2>/dev/null || ls -laR "$real_cfg" 2>/dev/null | md5sum) || real_before=none

OC="$SB/.config/opencode"
./opencode/install.sh "$OC" > "$SB/install.log" 2>&1
chk "commands installed"          'test -f "$OC/commands/harness-plan.md" && test -f "$OC/commands/harness-worktree.md"'
chk "all five commands"           '[ "$(ls "$OC/commands" | wc -l | tr -d " ")" = "5" ]'
chk "skills installed"            'test -f "$OC/skills/harness-plan/SKILL.md" && grep -q "^name: harness-plan$" "$OC/skills/harness-plan/SKILL.md"'
chk "all five skills"             '[ "$(find "$OC/skills" -name SKILL.md | wc -l | tr -d " ")" = "5" ]'
chk "AGENTS.md installed"         'grep -q "Read the code first" "$OC/AGENTS.md"'
chk "opencode.json not touched"   '! test -f "$OC/opencode.json"'
chk "agents not installed by default" '! test -d "$OC/agents"'

printf '# My rules\nmy own rule\n' > "$OC/AGENTS.md"
./opencode/install.sh "$OC" > "$SB/install2.log" 2>&1
./opencode/install.sh "$OC" > "$SB/install3.log" 2>&1
chk "existing rules kept"         'grep -q "my own rule" "$OC/AGENTS.md"'
chk "harness block merged"        'grep -q "Read the code first" "$OC/AGENTS.md"'
chk "idempotent: one block"       '[ "$(grep -c "agent-harness-configs:begin" "$OC/AGENTS.md")" = "1" ]'
chk "backup written"              'grep -q "my own rule" "$OC/AGENTS.md.bak"'

./opencode/install.sh --with-agents "$OC" > "$SB/install4.log" 2>&1
chk "generic agents converted"    '[ "$(ls "$OC/agents" | wc -l | tr -d " ")" = "16" ]'
chk "graph agents skipped"        '! test -e "$OC/agents/claim-refuter.md" && ! test -e "$OC/agents/plan-investigator.md"'
chk "no claude-only frontmatter"  '! grep -lE "^(tools|color|model|name):" "$OC"/agents/*.md'
chk "every agent is a subagent"   '[ "$(grep -l "^mode: subagent$" "$OC"/agents/*.md | wc -l | tr -d " ")" = "16" ]'
chk "tools mapped to permission"  'grep -q "\"git \*\": allow" "$OC/agents/api-architect.md" && grep -q "edit: deny" "$OC/agents/api-architect.md"'
chk "names unqualified"           '! grep -l "harness:" "$OC"/agents/*.md'
chk "examples stripped"           '! grep -qE "^description:.*(<example>|Examples:)" "$OC"/agents/*.md'
printf -- '---\ndescription: mine\nmode: subagent\n---\nmy agent\n' > "$OC/agents/pr-review.md"
./opencode/install.sh --with-agents "$OC" > "$SB/install5.log" 2>&1
chk "user agent never overwritten" 'grep -q "my agent" "$OC/agents/pr-review.md" && grep -qi "skipped" "$SB/install5.log"'

# Behavioral: when the opencode CLI is present, prove OpenCode itself accepts everything.
if command -v opencode >/dev/null; then
  mkdir -p "$SB/proj" && git -C "$SB/proj" init -q
  export HOME="$SB" XDG_CONFIG_HOME="$SB/.config" XDG_DATA_HOME="$SB/.local/share" XDG_CACHE_HOME="$SB/.cache" XDG_STATE_HOME="$SB/.local/state"
  (cd "$SB/proj" && opencode debug config > "$SB/cfg.out" 2>&1)
  chk "opencode: config valid"    'grep -q "\"harness-plan\"" "$SB/cfg.out" && ! grep -q "Configuration is invalid" "$SB/cfg.out"'
  (cd "$SB/proj" && opencode debug skill > "$SB/skill.out" 2>&1)
  chk "opencode: skills listed"   'grep -q "\"name\": \"harness-review\"" "$SB/skill.out"'
  (cd "$SB/proj" && opencode debug agent api-architect > "$SB/agent.out" 2>&1)
  chk "opencode: agent loads"     'grep -q "\"mode\": \"subagent\"" "$SB/agent.out"'
else
  echo "  skip opencode CLI checks (opencode not installed)"
fi

real_after=$(ls -laR "$real_cfg" 2>/dev/null | grep -v node_modules | md5 -q 2>/dev/null || ls -laR "$real_cfg" 2>/dev/null | md5sum) || real_after=none
chk "real opencode config untouched" '[ "$real_before" = "$real_after" ]'

exit $fail
