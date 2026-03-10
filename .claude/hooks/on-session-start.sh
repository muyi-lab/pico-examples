#!/usr/bin/env bash
# Injected into Claude context at session start.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "=== pico-examples project ==="
echo "CMake cross-compile for RP2040 / RP2350 (Raspberry Pi Pico family)"
echo "Build tool: python3 runner/workflow_runner.py"
echo ""

echo "--- Available workflows ---"
for f in "$PROJECT_DIR"/workflows/*.yaml; do
    name=$(basename "$f" .yaml)
    desc=$(grep -m1 'description:' "$f" | sed 's/description:[[:space:]]*//' | sed 's/^>//' | tr -d '"' | xargs || true)
    echo "  $name — $desc"
done
echo ""

echo "--- Last build status ---"
STATE="$PROJECT_DIR/workflow_state.json"
if [[ -f "$STATE" ]]; then
    python3 - "$STATE" <<'EOF'
import json, sys
data = json.load(open(sys.argv[1]))
workflow = data.get("workflow", "unknown")
steps = data.get("steps", {})
statuses = [f"  {k}: {v.get('status','?')}" for k, v in steps.items()]
all_ok = all(v.get("status") == "completed" for v in steps.values())
print(f"Workflow: {workflow}  ({'OK' if all_ok else 'FAILED'})")
print("\n".join(statuses))
EOF
else
    echo "  No workflow_state.json found — no build recorded yet."
fi
echo ""

echo "--- Git status ---"
cd "$PROJECT_DIR"
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
uncommitted=$(git status --porcelain 2>/dev/null | wc -l)
echo "  Branch: $branch  |  Uncommitted files: $uncommitted"
