#!/usr/bin/env bash
# =============================================================================
# board_diag_report.sh - Collect board diagnostic results into a JSON report
# =============================================================================
# Reads the most recent log for each check_board subcommand (via symlinks) and
# writes a consolidated board_diag_report.json to LOG_DIR.
#
# Environment variables:
#   PICO_BOARD    Board name for the report (default: pico)
#   SERIAL_PORT   Serial port for the report (default: /dev/ttyS4)
#   BAUD_RATE     Baud rate for the report (default: 115200)
#   LOG_DIR       Directory containing check_board_*.log files (default: logs)
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
PICO_BOARD="${PICO_BOARD:-pico}"
SERIAL_PORT="${SERIAL_PORT:-/dev/ttyS4}"
BAUD_RATE="${BAUD_RATE:-115200}"
REPORT_FILE="${LOG_DIR}/board_diag_report_${TIMESTAMP}.json"
REPORT_LATEST="${LOG_DIR}/board_diag_report.json"

log "=== Board Diagnostic Report ==="
log "Board       : ${PICO_BOARD}"
log "Serial port : ${SERIAL_PORT} @ ${BAUD_RATE}"
log "Report file : ${REPORT_FILE}"
log "Log         : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Read status for a single check_board subcommand from its symlinked log.
# Returns: passed | failed | skipped | not_run
check_status() {
    local subcommand="$1"
    local log_path="${LOG_DIR}/check_board_${subcommand}.log"

    if [ ! -f "${log_path}" ]; then
        echo "not_run"
        return
    fi

    # Skipped (flash_test only)
    if grep -q "PASSED (skipped)" "${log_path}" 2>/dev/null; then
        echo "skipped"
        return
    fi

    # Explicit PASSED / COMPLETE markers written by check_board.sh
    if grep -qP '(PASSED|COMPLETE)\s*===' "${log_path}" 2>/dev/null; then
        echo "passed"
        return
    fi

    # Any ERROR: line means the script hit fail()
    if grep -q "^[^]]*] ERROR:" "${log_path}" 2>/dev/null; then
        echo "failed"
        return
    fi

    echo "unknown"
}

# Extract a single detail line from a log file (first match of a grep pattern).
log_detail() {
    local log_path="$1"
    local pattern="$2"
    if [ -f "${log_path}" ]; then
        grep -oP "${pattern}" "${log_path}" 2>/dev/null | head -1 || true
    fi
}

# JSON-escape a plain string (handles backslash and double-quote only;
# sufficient for the controlled strings written by check_board.sh).
json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "${s}"
}

# ---------------------------------------------------------------------------
# Collect per-check status
# ---------------------------------------------------------------------------
USB_STATUS=$(check_status "usb")
PICOTOOL_STATUS=$(check_status "picotool")
SERIAL_STATUS=$(check_status "serial")
FLASH_STATUS=$(check_status "flash_test")
DEBUG_STATUS=$(check_status "debug_probe")

log "Check results:"
log "  usb         : ${USB_STATUS}"
log "  picotool    : ${PICOTOOL_STATUS}"
log "  serial      : ${SERIAL_STATUS}"
log "  flash_test  : ${FLASH_STATUS}"
log "  debug_probe : ${DEBUG_STATUS}"

# ---------------------------------------------------------------------------
# Collect extra detail (best-effort — empty string if not found)
# ---------------------------------------------------------------------------
PICOTOOL_VER=$(log_detail "${LOG_DIR}/check_board_picotool.log" '(?<=picotool version: ).+')
USB_MODE=$(log_detail "${LOG_DIR}/check_board_usb.log"          '(?<=Mode: ).+')
DEBUG_CAP=$(log_detail "${LOG_DIR}/check_board_debug_probe.log" '(?<=Debug capability: ).+')

# ---------------------------------------------------------------------------
# Determine overall status
#   passed     — all non-debug checks passed or were intentionally skipped
#   failed     — at least one non-debug check failed
#   incomplete — at least one check was not run (but none failed)
# ---------------------------------------------------------------------------
OVERALL="passed"
for STATUS in "${USB_STATUS}" "${PICOTOOL_STATUS}" "${SERIAL_STATUS}" "${FLASH_STATUS}"; do
    case "${STATUS}" in
        failed)
            OVERALL="failed"
            break
            ;;
        not_run|unknown)
            [ "${OVERALL}" != "failed" ] && OVERALL="incomplete"
            ;;
    esac
done

log "Overall status: ${OVERALL}"

# ---------------------------------------------------------------------------
# Write JSON report
# ---------------------------------------------------------------------------
ISO_TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

cat > "${REPORT_FILE}" <<EOF
{
  "timestamp":   "$(json_str "${ISO_TS}")",
  "board":       "$(json_str "${PICO_BOARD}")",
  "serial_port": "$(json_str "${SERIAL_PORT}")",
  "baud_rate":   "$(json_str "${BAUD_RATE}")",
  "checks": {
    "usb":         "$(json_str "${USB_STATUS}")",
    "picotool":    "$(json_str "${PICOTOOL_STATUS}")",
    "serial":      "$(json_str "${SERIAL_STATUS}")",
    "flash_test":  "$(json_str "${FLASH_STATUS}")",
    "debug_probe": "$(json_str "${DEBUG_STATUS}")"
  },
  "details": {
    "picotool_version": "$(json_str "${PICOTOOL_VER}")",
    "usb_mode":         "$(json_str "${USB_MODE}")",
    "debug_capability": "$(json_str "${DEBUG_CAP}")"
  },
  "overall": "$(json_str "${OVERALL}")"
}
EOF

# Stable symlink so callers can always reference board_diag_report.json
ln -sf "$(basename "${REPORT_FILE}")" "${REPORT_LATEST}"

log "Report written → ${REPORT_FILE}"
log "Symlink updated → ${REPORT_LATEST}"
log "=== Board diagnostic report PASSED ==="
exit 0
