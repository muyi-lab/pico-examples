#!/usr/bin/env bash
# PreToolUse hook for Bash — blocks direct cmake/make/compiler invocations.
# Claude Code passes the tool input as JSON on stdin.
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('command',''))" 2>/dev/null || true)

# Allow if routed through the workflow runner
if echo "$COMMAND" | grep -q "workflow_runner"; then
    exit 0
fi

# Block bare cmake / make / compiler calls
if echo "$COMMAND" | grep -qE '^\s*(cmake|make|ninja|arm-none-eabi-gcc|arm-none-eabi-g\+\+)\b'; then
    echo "ERROR: Direct use of cmake/make/compiler is not allowed in this project." >&2
    echo "" >&2
    echo "Use the workflow runner instead:" >&2
    echo "  python3 runner/workflow_runner.py workflows/build_example.yaml --param target=<name>" >&2
    echo "" >&2
    echo "See CLAUDE.md and .claude/skills/build/SKILL.md for details." >&2
    exit 1
fi

exit 0
