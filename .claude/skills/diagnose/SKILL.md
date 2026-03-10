---
name: diagnose
description: >
  Triggers on: build failure, "error", "failed", "why did it fail",
  log inspection, artifact missing, any post-build analysis request,
  "check board", "检查", "diagnose".
context: fork
---

# Diagnose Skill

Run as a subagent to keep the main context clean.

## Steps

1. Read `workflow_state.json` to find the failed step:
   ```bash
   cat workflow_state.json
   ```

2. Identify the failing step (look for `"status": "failed"` or non-zero `exit_code`).

3. Read the corresponding log:
   ```
   logs/<step_id>.log
   ```
   Common logs: `check_toolchain.log`, `setup_sdk.log`, `cmake_configure.log`,
   `build_target.log`, `verify_output.log`

4. Analyze the error and report:
   - The exact failure message
   - Root cause (missing tool, bad config, source error, etc.)
   - Recommended fix

5. If the fix is a configuration change, suggest the corrected workflow command:
   ```bash
   python3 runner/workflow_runner.py workflows/build_example.yaml \
     --param target=<name> [--param KEY=VALUE ...]
   ```
