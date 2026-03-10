#!/usr/bin/env bash
# =============================================================================
# reboot_bootsel.sh - Enter BOOTSEL mode with retry
# =============================================================================
# Attempts to put the RP2040/RP2350 into USB BOOTSEL (mass-storage) mode.
# Primary method: reboot_pico (X4 GPIO control, always works).
# Fallback method: picotool reboot -f -u (requires USB-capable firmware).
# Retries up to MAX_ATTEMPTS times, verifying USB enumeration after each try.
#
# Environment variables:
#   MAX_ATTEMPTS  Number of BOOTSEL attempts (default: 3)
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
MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"

log "=== Reboot to BOOTSEL ==="
log "Max attempts : ${MAX_ATTEMPTS}"
log "Log          : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Helper: check if board is in BOOTSEL via lsusb (vendor 2e8a)
# ---------------------------------------------------------------------------
in_bootsel() {
    command -v lsusb &>/dev/null && lsusb 2>/dev/null | grep -qi '2e8a'
}

# ---------------------------------------------------------------------------
# Retry loop
# ---------------------------------------------------------------------------
ATTEMPT=0
while [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    log "Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: triggering BOOTSEL mode..."

    if command -v reboot_pico &>/dev/null; then
        # Primary: X4 GPIO control — works regardless of running firmware
        log "  Method: reboot_pico (GPIO)"
        reboot_pico 2>&1 | tee -a "${LOG_FILE}" || true
    elif command -v picotool &>/dev/null; then
        # Fallback: picotool reboot -f -u (requires USB-capable firmware)
        log "  Method: picotool reboot -f -u"
        picotool reboot -f -u 2>&1 | tee -a "${LOG_FILE}" || true
    else
        fail "Neither reboot_pico nor picotool found — cannot trigger BOOTSEL"
    fi

    # Allow USB to enumerate
    sleep 1

    if in_bootsel; then
        log "BOOTSEL confirmed: RP2040/RP2350 device (vendor 2e8a) visible on USB"
        log "=== reboot_bootsel PASSED ==="
        exit 0
    fi

    if [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; then
        log "Board not detected in BOOTSEL mode — retrying in 2s..."
        sleep 2
    fi
done

fail "Board did not enter BOOTSEL mode after ${MAX_ATTEMPTS} attempt(s)"
