---
name: smoke_test
description: >
  Use when the user wants to build firmware, flash it to a physical Pico board,
  and verify the output.
  Triggers on: "smoke test", "smoke_test", "end-to-end test", "flash and verify",
  "run on hardware", "test on board", "verify uart", "冒烟测试".
context: fork
---

# Smoke Test Skill

Run as a subagent to keep the main context clean.

## Steps

1. Identify the target and expected UART pattern from the user's request.

2. Run the smoke test workflow:
   ```bash
   python3 runner/workflow_runner.py workflows/smoke_test.yaml \
     --param target=<name> \
     --param uart_expect_pattern="<regex>"
   # Example: hello_serial outputs "Hello, world!" (lowercase w)
   #   --param uart_expect_pattern="Hello, world"
   ```

3. If the target produces no serial output (e.g. blink), omit `uart_expect_pattern`:
   ```bash
   python3 runner/workflow_runner.py workflows/smoke_test.yaml \
     --param target=blink
   ```

4. If a step fails, read the corresponding log. Each script writes a timestamped
   file and a stable symlink pointing to the latest run:
   ```
   logs/verify_artifact_<YYYYMMDD_HHMMSS>.log   ← timestamped
   logs/verify_artifact.log                      ← symlink → latest

   logs/reboot_bootsel_<YYYYMMDD_HHMMSS>.log
   logs/reboot_bootsel.log

   logs/flash_firmware_<YYYYMMDD_HHMMSS>.log
   logs/flash_firmware.log

   logs/capture_uart_<YYYYMMDD_HHMMSS>.log
   logs/capture_uart.log

   logs/uart_<target>.log                        ← raw UART capture (no timestamp)

   logs/smoke_test_report_<YYYYMMDD_HHMMSS>.json ← timestamped report
   logs/smoke_test_report.json                   ← symlink → latest report
   ```

5. Analyze the failure and report:
   - The exact failure message
   - Root cause (artifact missing, BOOTSEL not triggered, flash error, UART pattern mismatch, etc.)
   - Recommended fix

6. If the target was not built yet, run build first:
   ```bash
   python3 runner/workflow_runner.py workflows/build_example.yaml \
     --param target=<name> [--param board=<board>]
   ```
   Then re-run the smoke test with `--resume` to skip completed steps.

## Regression suite

To run all 10 standalone targets in sequence:
```bash
python3 scripts/run_regression.py
```
Options:
- `--board pico`            board type (default: pico)
- `--log-dir logs/regression` per-target log directory
- `--stop-on-fail`          abort after first failure
- `--targets hello_serial,rand` run a subset

Report saved to `logs/regression/regression_report.json`.

## Parameter reference

| Param                  | Default        | Notes                                   |
|------------------------|----------------|-----------------------------------------|
| `target`               | hello_serial   | CMake target name                       |
| `board`                | pico           | pico \| pico_w \| pico2 \| pico2_w     |
| `platform`             | rp2040         | rp2040 \| rp2350-arm-s \| rp2350-riscv |
| `uart_expect_pattern`  | ""             | Regex; empty = skip UART check. For hello_serial use `"Hello, world"` (lowercase w) |
| `uart_timeout_seconds` | 10             | Seconds to wait for UART output         |
| `boot_wait_seconds`    | 5              | Seconds to wait after firmware boot     |
| `flash_method`         | picotool       | picotool \| uf2_copy \| openocd         |
| `serial_port`          | /dev/ttyS4     | UART device for capture                 |
