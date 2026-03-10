#!/usr/bin/env bash
# =============================================================================
# flash_firmware.sh - Flash firmware to RP2040/RP2350
# =============================================================================
# Supports three flash methods selected via FLASH_METHOD:
#
#   picotool  (default) — picotool load <file>.uf2 --force
#   uf2_copy            — copy .uf2 to USB mass-storage mount point
#   openocd             — flash .elf via OpenOCD + CMSIS-DAP/SWD
#
# Environment variables:
#   TARGET        CMake target name (e.g. blink, hello_serial) — required
#   BUILD_DIR     CMake build directory (default: build)
#   FLASH_METHOD  picotool | uf2_copy | openocd (default: picotool)
#   LOG_DIR       Directory for log files (default: logs)
# =============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0" .sh)"
LOG_DIR="${LOG_DIR:-logs}"
mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"
ln -sf "$(basename "${LOG_FILE}")" "${LOG_DIR}/${SCRIPT_NAME}.log"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
fail() { log "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
TARGET="${TARGET:-}"
FLASH_METHOD="${FLASH_METHOD:-picotool}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"

[ -z "${TARGET}" ] && fail "TARGET env var is required (e.g. TARGET=blink)"

log "=== Flash Firmware: ${TARGET} ==="
log "Method    : ${FLASH_METHOD}"
log "Build dir : ${BUILD_DIR}"
log "Log       : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Locate artifacts
# ---------------------------------------------------------------------------
UF2_FILE=$(find "${BUILD_DIR}" -name "${TARGET}.uf2" 2>/dev/null | head -1 || true)
ELF_FILE=$(find "${BUILD_DIR}" -name "${TARGET}.elf" 2>/dev/null | head -1 || true)

[ -z "${UF2_FILE}" ] && fail "${TARGET}.uf2 not found under ${BUILD_DIR}"
log "UF2 : ${UF2_FILE}"
[ -n "${ELF_FILE}" ] && log "ELF : ${ELF_FILE}"

# ---------------------------------------------------------------------------
# Flash method: picotool
# ---------------------------------------------------------------------------
flash_picotool() {
    if ! command -v picotool &>/dev/null; then
        fail "picotool not found — install from https://github.com/raspberrypi/picotool"
    fi
    log "Running: picotool load ${UF2_FILE} --force"
    if ! picotool load "${UF2_FILE}" --force 2>&1 | tee -a "${LOG_FILE}"; then
        fail "picotool load failed for ${UF2_FILE}"
    fi
    log "Running: picotool reboot"
    picotool reboot 2>&1 | tee -a "${LOG_FILE}" || true
}

# ---------------------------------------------------------------------------
# Flash method: uf2_copy (USB mass-storage drag-and-drop)
# ---------------------------------------------------------------------------
flash_uf2_copy() {
    # Locate the RPI-RP2 mount point (auto-mounted in BOOTSEL mode)
    MOUNT_POINT=""
    for candidate in \
        /media/"${USER:-root}"/RPI-RP2 \
        /media/RPI-RP2 \
        /run/media/"${USER:-root}"/RPI-RP2 \
        /mnt/pico
    do
        if [ -d "${candidate}" ]; then
            MOUNT_POINT="${candidate}"
            break
        fi
    done

    # Also try findmnt as last resort
    if [ -z "${MOUNT_POINT}" ] && command -v findmnt &>/dev/null; then
        MOUNT_POINT=$(findmnt -rno TARGET -S LABEL=RPI-RP2 2>/dev/null || true)
    fi

    if [ -z "${MOUNT_POINT}" ]; then
        fail "RPI-RP2 USB mass-storage not found — ensure board is in BOOTSEL mode and mounted"
    fi

    log "Mount point : ${MOUNT_POINT}"
    log "Copying ${UF2_FILE} → ${MOUNT_POINT}/"
    cp "${UF2_FILE}" "${MOUNT_POINT}/"
    sync
    # Board reboots automatically after UF2 copy
}

# ---------------------------------------------------------------------------
# Flash method: openocd (SWD via debug probe)
# ---------------------------------------------------------------------------
flash_openocd() {
    if ! command -v openocd &>/dev/null; then
        fail "openocd not found — install: sudo apt-get install openocd"
    fi

    if [ -z "${ELF_FILE}" ]; then
        fail "${TARGET}.elf not found — required for OpenOCD flashing"
    fi

    log "Running: openocd (CMSIS-DAP → ${ELF_FILE})"
    openocd \
        -f interface/cmsis-dap.cfg \
        -f target/rp2040.cfg \
        -c "adapter speed 5000" \
        -c "program ${ELF_FILE} verify reset exit" \
        2>&1 | tee -a "${LOG_FILE}"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${FLASH_METHOD}" in
    picotool) flash_picotool ;;
    uf2_copy) flash_uf2_copy ;;
    openocd)  flash_openocd  ;;
    *)        fail "Unknown FLASH_METHOD '${FLASH_METHOD}' — expected: picotool | uf2_copy | openocd" ;;
esac

log "=== flash_firmware PASSED ==="
exit 0
