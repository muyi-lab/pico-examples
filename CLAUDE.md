# pico-examples

RP2040/RP2350 example code for Raspberry Pi Pico, cross-compiled with CMake.

## Rules

- **All build operations must go through the workflow runner** — never run `cmake`, `make`, or `arm-none-eabi-gcc` directly.
- To build an example:
  ```
  python3 runner/workflow_runner.py workflows/build_example.yaml --param target=hello_serial
  ```
- Override defaults: `--param board=pico_w`, `--param platform=rp2350-arm-s`, etc.

## Reference

- Available workflows: `workflows/` (yaml files)
- Available skills: `.claude/skills/` (build, diagnose)
- Flash tool: `picotool load <file>.uf2 --force && picotool reboot`
- UART: `/dev/ttyS4` @ 115200 baud
