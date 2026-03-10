---
name: build
description: >
  Triggers on: "build", "compile", "编译", "make target", ".uf2",
  "flash", or any request to produce firmware for a named example.
---

# Build Skill

Run the workflow runner with the requested target:

```bash
python3 runner/workflow_runner.py workflows/build_example.yaml \
  --param target=$ARGUMENTS
```

## Optional overrides

| Param      | Default   | Options                                  |
|------------|-----------|------------------------------------------|
| board      | pico      | pico, pico_w, pico2, pico2_w             |
| platform   | rp2040    | rp2040, rp2350-arm-s, rp2350-riscv       |
| build_type | Release   | Release, Debug, MinSizeRel               |

Example with overrides:
```bash
python3 runner/workflow_runner.py workflows/build_example.yaml \
  --param target=blink --param board=pico_w --param platform=rp2040
```

After a successful build the .uf2 is under `build/` in a subdirectory
matching the source path (e.g. `build/hello_world/serial/hello_serial.uf2`).

Flash with:
```bash
picotool load <file>.uf2 --force && picotool reboot
```
