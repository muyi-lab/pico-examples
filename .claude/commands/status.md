Show the current project state: last workflow result, git branch, and available targets.

Steps:
1. Read `workflow_state.json` and summarise each step's status and timestamp.
2. Run `git status --short` and report branch + uncommitted file count.
3. List `workflows/*.yaml` with their descriptions.
4. List any `.uf2` files under `build/` (find build -name '*.uf2' 2>/dev/null).
