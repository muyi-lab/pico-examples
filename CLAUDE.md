# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Hardware Environment

This repo runs on a **Radxa X4** host (Intel N100) with an **onboard RP2040** that drives the 40-pin GPIO header and bridges to an attached Raspberry Pi Pico:

```
Radxa X4
├── Intel N100 ──UART(/dev/ttyS4)──► Onboard RP2040 ──► 40-pin header
│                                                           ├── GPIO7  → Pico BOOTSEL
│                                                           ├── GPIO17 → Pico RUN/RESET
│                                                           ├── GPIO0  ← Pico TX (UART)
│                                                           └── GPIO1  → Pico RX (UART)
└── USB port ──────────────────────────────────────────────► Pico USB (/dev/ttyACM0)
```

- Pico hardware UART (GPIO0/1) → `/dev/ttyS4` (via 40-pin header → onboard RP2040)
- Pico USB CDC → `/dev/ttyACM0`
- `reboot_pico` pulses `gpiochip0` lines 7 & 17 to hardware-reset the Pico into BOOTSEL

Current local board is **pico (rp2040)**; build directory is `build/`. A separate `build-pico2/` exists for pico2 (rp2350).

## Prerequisites (one-time setup)

Install build tools if not already present:
```sh
sudo apt update -y
sudo apt install -y git cmake gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib
```

SDK is already cloned at `/home/macro/work/pico/pico-sdk` with submodules initialised.

## Build Commands

### Configure (first time or new board)
```sh
mkdir build && cd build && cmake .. -DPICO_SDK_PATH=/home/macro/work/pico/pico-sdk -DPICO_BOARD=pico -DPICO_NO_PICOTOOL=1
```

For pico2 (RP2350):
```sh
mkdir build-pico2 && cd build-pico2 && cmake .. -DPICO_SDK_PATH=/home/macro/work/pico/pico-sdk -DPICO_BOARD=pico2 -DPICO_NO_PICOTOOL=1
```

> Always pass `-DPICO_NO_PICOTOOL=1` — the SDK-side picotool integration attempts a network fetch during CMake configure without it.

### Build a single target
```sh
cd build && make hello_serial -j$(nproc)
```

Output artifacts for a target like `hello_serial`:
- `build/hello_world/serial/hello_serial.elf` — load with picotool or debugger
- `build/hello_world/serial/hello_serial.uf2` — drag-and-drop via USB mass storage

### Build all examples
```sh
cd build && make -j$(nproc)
```

### Fix a stuck CMakeCache
```sh
rm build/CMakeCache.txt
# then reconfigure with cmake ..
```

## Flash to Board

### Method 1 — picotool (preferred for iteration)
```sh
reboot_pico && sleep 3 && picotool load build/hello_world/serial/hello_serial.elf --verify --execute
```

`picotool` accepts `.elf`, `.uf2`, or `.bin`. Verify what is currently flashed:
```sh
picotool info -a
```

### Method 2 — UF2 drag-and-drop (via Radxa X4 software GPIO reset)
The `reboot_pico` command wraps this GPIO sequence from [Radxa X4 docs](https://docs.radxa.com/en/x/x4/software/flash?flash_way=Software):
```sh
# Pulse gpiochip0 lines 7 (BOOTSEL) and 17 (RESET) to enter USB bootloader
sudo gpioset gpiochip0 17=1
sudo gpioset gpiochip0 7=1
sleep 1
sudo gpioset gpiochip0 17=0
sudo gpioset gpiochip0 7=0
# RP2040 now appears as a USB mass storage device — copy the .uf2 file to it
cp build/hello_world/serial/hello_serial.uf2 /media/$USER/RPI-RP2/
```

### Method 3 — Hardware BOOTSEL button
Press and hold the BOOTSEL button on the Pico, then connect USB. The board appears as a USB mass storage device; drag the `.uf2` onto it.

## Verify Output

**USB CDC** (e.g. `hello_usb`) — no extra hardware needed:
```sh
timeout 5 cat /dev/ttyACM0
```

**Hardware UART** (e.g. `hello_serial`) — via 40-pin header → `/dev/ttyS4`:
```sh
stty -F /dev/ttyS4 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts
timeout 10 cat /dev/ttyS4
```

Or with minicom (interactive):
```sh
sudo minicom -D /dev/ttyS4 -b 115200
```

### Content Validation (required — do not skip)

Capturing output is not sufficient. Always validate the content matches what the example is expected to print. Use `grep` to assert the expected string is present and fail clearly if it is not:

```sh
# stty MUST be a separate command before capture — chaining with && drops output
stty -F /dev/ttyS4 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts
OUTPUT=$(timeout 5 cat /dev/ttyS4)
echo "$OUTPUT"
echo "$OUTPUT" | grep -q "Hello, world!" && echo "PASS: output matched" || echo "FAIL: expected output not found"
```

For USB CDC examples (e.g. `hello_usb`):
```sh
OUTPUT=$(timeout 5 cat /dev/ttyACM0)
echo "$OUTPUT"
echo "$OUTPUT" | grep -q "Hello, world!" && echo "PASS: output matched" || echo "FAIL: expected output not found"
```

**What to check:**
- The expected string appears at least once in the captured output
- Output repeats at the correct interval (count lines: `echo "$OUTPUT" | grep -c "Hello, world!"` should be > 1 for a 5 s window)
- No garbled/empty output (indicates wrong baud rate or UART misconfiguration)

Save validated output to a timestamped log:
```sh
LOG_DIR="build/hello_world/serial"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/hello_serial_$(date +%Y%m%d_%H%M%S).log"
stty -F /dev/ttyS4 115200 cs8 -cstopb -parenb -ixon -ixoff -crtscts
OUTPUT=$(timeout 10 cat /dev/ttyS4 | tr -d '\0')
echo "$OUTPUT" | tee "$LOG_FILE"
echo "$OUTPUT" | grep -q "Hello, world!" && echo "PASS" | tee -a "$LOG_FILE" || echo "FAIL" | tee -a "$LOG_FILE"
```

Log file naming convention: `<target>_YYYYMMDD_HHMMSS.log` placed in the same directory as the build artifacts. Always `mkdir -p` the directory before writing — build subdirectories may not exist until the target is built.

## Repository Architecture

Each example is self-contained in its own directory with a local `CMakeLists.txt`. The root `CMakeLists.txt` aggregates all subdirectories via `add_subdirectory`. The helper `add_subdirectory_exclude_platforms()` skips examples incompatible with the current `PICO_PLATFORM`.

**Key CMake patterns in each example:**
- `add_executable(<target> <source>.c)` — define the binary
- `target_link_libraries(<target> pico_stdlib ...)` — link SDK libraries
- `pico_add_extra_outputs(<target>)` — generate `.uf2`, `.bin`, `.hex`, `.map`
- `pico_enable_stdio_usb(<target> 1)` / `pico_enable_stdio_uart(<target> 1)` — select stdio transport

**Platform-specific examples** (RP2350-only): `dcp/`, `otp/`, `sha/`, `hstx/`, `encrypted/`, `bootloaders/`
**Connectivity examples** (Pico W only): `pico_w/wifi/`, `pico_w/bt/` — require `PICO_BOARD=pico_w`
**FreeRTOS examples**: require `-DFREERTOS_KERNEL_PATH=<path>`

SDK minimum version required: **2.2.0**

## Code Style

- 4 spaces for indentation, no tabs
- Opening braces on the same line
- Braces required except for single-line `if` statements
- Lowercase underscore-separated target and file names (e.g. `hello_uart`, `pwm_led_fade`)

## Testing

No automated test suite. Validation = successful CMake configure + clean build of affected targets. For hardware verification, flash the `.elf` and check serial output as described above.

Upstream PRs go against the `develop` branch (not `master`).

## First-Open Workflow

**Every time Claude Code opens this repository for the first time in a session, perform these steps before any other work:**

1. **Check repo state**
   ```sh
   git status --short --branch
   ```

2. **Create a dated working branch** named `claude_code_change_YYYYMMDD` (use today's date):
   ```sh
   git checkout -b claude_code_change_$(date +%Y%m%d)
   ```

3. **Push the branch and set upstream tracking**:
   ```sh
   git push -u origin claude_code_change_$(date +%Y%m%d)
   ```

4. **Ensure `CLAUDE.md` exists**. If it is missing, run `/init` to generate it from the codebase, then commit and push:
   ```sh
   git add CLAUDE.md
   git commit -m "Add CLAUDE.md with project guidance"
   git push
   ```

5. **Confirm** the remote branch is up to date before starting feature work:
   ```sh
   git status
   ```

All subsequent changes in the session go on this branch. Open a PR against `master` when the work is ready for review.
