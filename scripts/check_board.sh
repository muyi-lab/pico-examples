#!/usr/bin/env bash
# =============================================================================
# check_board.sh - Board connectivity and capability diagnostics
# =============================================================================
# Usage:
#   check_board.sh <subcommand>
#
# Subcommands:
#   usb          Detect RP2040/RP2350 device on USB bus
#   picotool     Verify picotool installation and board detection
#   serial       Check UART serial port accessibility
#   flash_test   Flash a test binary via picotool (skips if RUN_FLASH_TEST!=true)
#   debug_probe  Detect OpenOCD, pyocd, and USB debug probe hardware
#
# Environment variables:
#   SERIAL_PORT    Serial device path (default: /dev/ttyS4)
#   BAUD_RATE      Baud rate (default: 115200)
#   RUN_FLASH_TEST Whether to actually flash a binary (default: true)
#   BUILD_DIR      CMake build directory for locating .uf2 (default: build)
#   LOG_DIR        Directory for log files (default: logs)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Subcommand — must be first so LOG_FILE can embed it
# ---------------------------------------------------------------------------
SUBCOMMAND="${1:-}"
if [ -z "${SUBCOMMAND}" ]; then
    echo "Usage: $(basename "$0") <usb|picotool|serial|flash_test|debug_probe>" >&2
    exit 1
fi

case "${SUBCOMMAND}" in
    usb|picotool|serial|flash_test|debug_probe) ;;
    *)
        echo "Unknown subcommand: '${SUBCOMMAND}'. Expected: usb|picotool|serial|flash_test|debug_probe" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Logging — per-subcommand timestamped file + stable symlink
# ---------------------------------------------------------------------------
SCRIPT_NAME="check_board_${SUBCOMMAND}"
LOG_DIR="${LOG_DIR:-logs}"
mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"
ln -sf "$(basename "${LOG_FILE}")" "${LOG_DIR}/${SCRIPT_NAME}.log"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
fail() { log "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
SERIAL_PORT="${SERIAL_PORT:-/dev/ttyS4}"
BAUD_RATE="${BAUD_RATE:-115200}"
RUN_FLASH_TEST="${RUN_FLASH_TEST:-true}"
BUILD_DIR="${BUILD_DIR:-build}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"

# ---------------------------------------------------------------------------
# Subcommand: usb
# ---------------------------------------------------------------------------
cmd_usb() {
    log "=== USB Check ==="
    log "Log : ${LOG_FILE}"

    if ! command -v lsusb &>/dev/null; then
        fail "lsusb not found. Install: sudo apt-get install usbutils"
    fi

    if ! command -v reboot_pico &>/dev/null; then
        fail "reboot_pico not found — cannot enter BOOTSEL mode"
    fi

    log "Entering BOOTSEL mode via reboot_pico..."
    reboot_pico 2>&1 | tee -a "${LOG_FILE}" || true
    sleep 1

    log "Scanning USB bus..."
    USB_OUT=$(lsusb 2>/dev/null || true)

    # Raspberry Pi Ltd vendor ID is 2e8a (RP2040 / RP2350)
    RPI_LINES=$(echo "${USB_OUT}" | grep -i '2e8a\|Raspberry Pi' || true)

    if [ -z "${RPI_LINES}" ]; then
        fail "No RP2040/RP2350 device detected on USB after reboot_pico (vendor 2e8a not found in lsusb output)"
    fi

    log "Detected Raspberry Pi device(s):"
    while IFS= read -r line; do
        log "  ${line}"
    done <<< "${RPI_LINES}"

    # Infer operating mode from USB product ID
    if echo "${RPI_LINES}" | grep -qi 'mass storage\|:0003\|:0004'; then
        log "Mode: BOOTSEL (USB mass-storage) — ready for UF2 flash"
    elif echo "${RPI_LINES}" | grep -qi 'cdc\|serial\|:0005\|:000a\|:000b\|:000c'; then
        log "Mode: Firmware running (CDC / custom USB)"
    else
        log "Mode: Device present (mode undetermined from product ID)"
    fi

    log "=== USB check PASSED ==="
}

# ---------------------------------------------------------------------------
# Subcommand: picotool
# ---------------------------------------------------------------------------
cmd_picotool() {
    log "=== picotool Check ==="
    log "Log : ${LOG_FILE}"

    if ! command -v picotool &>/dev/null; then
        fail "picotool not found. Build from source: https://github.com/raspberrypi/picotool"
    fi

    PTOOL_VER=$(picotool version 2>&1 | head -1 || true)
    log "picotool version: ${PTOOL_VER}"

    log "Querying connected board (picotool info)..."
    PTOOL_INFO=$(picotool info 2>&1 || true)

    if echo "${PTOOL_INFO}" | grep -qi 'no device\|not found\|error\|unable'; then
        log "WARNING: picotool could not detect a board"
        log "  Run 'reboot_pico' to enter BOOTSEL mode, then retry"
        log "  Or ensure the running firmware exposes USB access"
        while IFS= read -r line; do
            log "  ${line}"
        done <<< "${PTOOL_INFO}"
    else
        log "Board info from picotool:"
        while IFS= read -r line; do
            log "  ${line}"
        done <<< "${PTOOL_INFO}"
    fi

    log "=== picotool check PASSED ==="
}

# ---------------------------------------------------------------------------
# Subcommand: serial
# ---------------------------------------------------------------------------
cmd_serial() {
    log "=== Serial Check ==="
    log "Port : ${SERIAL_PORT}"
    log "Baud : ${BAUD_RATE}"
    log "Log  : ${LOG_FILE}"

    if [ ! -e "${SERIAL_PORT}" ]; then
        fail "Serial port not found: ${SERIAL_PORT}"
    fi

    if [ ! -c "${SERIAL_PORT}" ]; then
        log "WARNING: ${SERIAL_PORT} exists but is not a character device"
    else
        log "Device type: character device (OK)"
    fi

    if [ ! -r "${SERIAL_PORT}" ]; then
        fail "Serial port not readable: ${SERIAL_PORT} — try: sudo usermod -aG dialout \$USER"
    fi
    log "Read permission: OK"

    if command -v stty &>/dev/null; then
        if stty -F "${SERIAL_PORT}" "${BAUD_RATE}" 2>/dev/null; then
            log "stty configured at ${BAUD_RATE} baud"
        else
            log "WARNING: stty configuration failed (port may be in use by another process)"
        fi
    else
        log "stty not available — skipping baud rate configuration check"
    fi

    log "=== serial check PASSED ==="
}

# ---------------------------------------------------------------------------
# Subcommand: flash_test
# ---------------------------------------------------------------------------
cmd_flash_test() {
    log "=== Flash Test ==="
    log "RUN_FLASH_TEST : ${RUN_FLASH_TEST}"
    log "Build dir      : ${BUILD_DIR}"
    log "Serial port    : ${SERIAL_PORT} @ ${BAUD_RATE}"
    log "Log            : ${LOG_FILE}"

    if [ "${RUN_FLASH_TEST}" != "true" ]; then
        log "Skipping flash test (RUN_FLASH_TEST=${RUN_FLASH_TEST})"
        log "=== flash_test PASSED (skipped) ==="
        exit 0
    fi

    # hello_serial is the test binary — it outputs "Hello, World!" over UART
    UF2_FILE=$(find "${BUILD_DIR}" -name "hello_serial.uf2" 2>/dev/null | head -1 || true)
    if [ -z "${UF2_FILE}" ]; then
        fail "hello_serial.uf2 not found in ${BUILD_DIR} — build it first:
  python3 runner/workflow_runner.py workflows/build_example.yaml --param target=hello_serial"
    fi
    log "Test binary: ${UF2_FILE}"

    if ! command -v picotool &>/dev/null; then
        fail "picotool not found — cannot flash. Install picotool first."
    fi

    if ! command -v reboot_pico &>/dev/null; then
        fail "reboot_pico not found — cannot trigger BOOTSEL mode automatically"
    fi

    log "Entering BOOTSEL mode via reboot_pico..."
    reboot_pico 2>&1 | tee -a "${LOG_FILE}" || true
    sleep 1

    log "Flashing ${UF2_FILE}..."
    if ! picotool load "${UF2_FILE}" --force 2>&1 | tee -a "${LOG_FILE}"; then
        fail "picotool load failed for ${UF2_FILE}"
    fi

    log "Rebooting board into firmware..."
    picotool reboot 2>&1 | tee -a "${LOG_FILE}" || true
    sleep 2

    # Configure serial port for raw reading
    stty -F "${SERIAL_PORT}" "${BAUD_RATE}" cs8 -cstopb -parenb raw -echo 2>/dev/null || true

    log "Reading UART output from ${SERIAL_PORT} (up to 5 seconds)..."
    UART_OUTPUT=$(timeout 5 cat "${SERIAL_PORT}" 2>/dev/null || true)

    log "UART output received:"
    while IFS= read -r line; do
        log "  ${line}"
    done <<< "${UART_OUTPUT}"

    if echo "${UART_OUTPUT}" | grep -q "Hello, world!"; then
        log "UART verification: 'Hello, world!' confirmed"
        log "=== flash_test PASSED ==="
    else
        fail "UART verification failed: 'Hello, World!' not found in output from ${SERIAL_PORT}"
    fi
}

# ---------------------------------------------------------------------------
# Subcommand: debug_probe
# ---------------------------------------------------------------------------
cmd_debug_probe() {
    log "=== Debug Probe Check ==="
    log "Log : ${LOG_FILE}"

    FOUND_TOOLS=false
    FOUND_HW=false

    # openocd
    if command -v openocd &>/dev/null; then
        OPENOCD_VER=$(openocd --version 2>&1 | head -1 || true)
        log "openocd    : ${OPENOCD_VER}"
        FOUND_TOOLS=true
    else
        log "openocd    : not installed"
    fi

    # pyocd
    if command -v pyocd &>/dev/null; then
        PYOCD_VER=$(pyocd --version 2>&1 | head -1 || true)
        log "pyocd      : ${PYOCD_VER}"
        FOUND_TOOLS=true
    else
        log "pyocd      : not installed"
    fi

    # USB debug probe hardware (Picoprobe 2e8a:000c, CMSIS-DAP, J-Link, ST-Link)
    if command -v lsusb &>/dev/null; then
        PROBE_LINES=$(lsusb 2>/dev/null | grep -i '2e8a:000c\|CMSIS-DAP\|J-Link\|ST-Link\|DAP-Link' || true)
        if [ -n "${PROBE_LINES}" ]; then
            log "USB debug probe hardware detected:"
            while IFS= read -r line; do
                log "  ${line}"
            done <<< "${PROBE_LINES}"
            FOUND_HW=true
        else
            log "USB debug probe hardware: none detected"
        fi
    else
        log "lsusb not available — skipping USB probe scan"
    fi

    if [ "${FOUND_TOOLS}" = "true" ] || [ "${FOUND_HW}" = "true" ]; then
        log "Debug capability: available"
    else
        log "Debug capability: not available (SWD debugging requires a debug probe + openocd/pyocd)"
    fi

    log "=== debug_probe check COMPLETE ==="
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${SUBCOMMAND}" in
    usb)         cmd_usb         ;;
    picotool)    cmd_picotool    ;;
    serial)      cmd_serial      ;;
    flash_test)  cmd_flash_test  ;;
    debug_probe) cmd_debug_probe ;;
esac
