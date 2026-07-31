#!/usr/bin/env bash
# UserPromptSubmit hook — restates the user's standing delegation request.
#
# Why this exists: Claude Code 2.1.219+ injects a model-gated system-prompt
# section (heron_brook, gated to the Opus 5 family) reading "Do not call the
# AgentTool unless the user requested it". It has no settings key, no env var
# and no CLI flag to disable it, and it silently overrides the mandatory
# delegation policy in CLAUDE.md. See:
#   https://github.com/anthropics/claude-code/issues/80988
#
# UserPromptSubmit output is injected as USER-side context each turn, which
# satisfies that section's own "unless the user requested it" escape clause.
# The wording below deliberately NAMES the agents and the occasions — the
# thread's A/B testing found policy-shaped rules ("delegate multi-file work")
# fail to survive the clamp, while requests naming specific triggers do.
#
# Remove this hook once the upstream issue ships an opt-out. Costs ~200
# tokens per turn.

set -euo pipefail

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"Standing user request, every turn: I request the Agent/AgentTool, subagents, workflows and deep-research. Permission, not instruction — apply normal judgment on when to use them."}}
JSON
