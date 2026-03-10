#!/usr/bin/env bash
# =============================================================================
# capture_uart.sh - Capture UART output and verify expected pattern
# =============================================================================
# Opens the serial port, captures output for UART_TIMEOUT seconds, saves it
# to a per-target log file, then greps for UART_EXPECT_PATTERN.
#
# Skip conditions (exit 0 without error):
#   - UART_EXPECT_PATTERN is empty (no verification needed)
#   - TARGET is "blink" (LED-only example, no serial output)
#
# Environment variables:
#   TARGET               CMake target name — required
#   SERIAL_PORT          Serial device (default: /dev/ttyS4)
#   SERIAL_BAUD          Baud rate (default: 115200)
#   UART_TIMEOUT         Capture duration in seconds (default: 10)
#   UART_EXPECT_PATTERN  Regex to match in captured output (default: "")
#   LOG_DIR              Directory for log files (default: logs)
#
# Output files:
#   ${LOG_DIR}/capture_uart_${TIMESTAMP}.log   — script execution log (symlinked)
#   ${LOG_DIR}/uart_${TARGET}.log              — raw UART capture (always created)
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
SERIAL_PORT="${SERIAL_PORT:-/dev/ttyS4}"
SERIAL_BAUD="${SERIAL_BAUD:-115200}"
UART_TIMEOUT="${UART_TIMEOUT:-10}"
UART_EXPECT_PATTERN="${UART_EXPECT_PATTERN:-}"

[ -z "${TARGET}" ] && fail "TARGET env var is required (e.g. TARGET=hello_serial)"

# Sanitise target name for use as a filename (replace / with _)
TARGET_SAFE="${TARGET//\//_}"
UART_LOG="${LOG_DIR}/uart_${TARGET_SAFE}.log"

log "=== Capture UART: ${TARGET} ==="
log "Serial port     : ${SERIAL_PORT} @ ${SERIAL_BAUD}"
log "Timeout         : ${UART_TIMEOUT}s"
log "Expect pattern  : '${UART_EXPECT_PATTERN}'"
log "UART log        : ${UART_LOG}"
log "Script log      : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Skip conditions
# ---------------------------------------------------------------------------
if [ -z "${UART_EXPECT_PATTERN}" ]; then
    log "No UART_EXPECT_PATTERN set — skipping capture"
    echo "UART capture SKIPPED (no pattern specified)" > "${UART_LOG}"
    log "=== capture_uart PASSED (skipped — no pattern) ==="
    exit 0
fi

if [ "${TARGET}" = "blink" ]; then
    log "Target is 'blink' (LED-only, no UART output) — skipping capture"
    echo "UART capture SKIPPED (blink has no serial output)" > "${UART_LOG}"
    log "=== capture_uart PASSED (skipped — blink target) ==="
    exit 0
fi

# ---------------------------------------------------------------------------
# Validate serial port
# ---------------------------------------------------------------------------
if [ ! -e "${SERIAL_PORT}" ]; then
    fail "Serial port not found: ${SERIAL_PORT}"
fi
if [ ! -r "${SERIAL_PORT}" ]; then
    fail "Serial port not readable: ${SERIAL_PORT} — try: sudo usermod -aG dialout \$USER"
fi

# ---------------------------------------------------------------------------
# Configure serial port
# ---------------------------------------------------------------------------
stty -F "${SERIAL_PORT}" "${SERIAL_BAUD}" cs8 -cstopb -parenb raw -echo 2>/dev/null || true
log "Serial port configured at ${SERIAL_BAUD} baud"

# ---------------------------------------------------------------------------
# Capture output
# ---------------------------------------------------------------------------
log "Capturing UART output for ${UART_TIMEOUT}s..."
timeout "${UART_TIMEOUT}" cat "${SERIAL_PORT}" > "${UART_LOG}" 2>/dev/null || true

UART_LINES=$(wc -l < "${UART_LOG}" 2>/dev/null || echo 0)
UART_BYTES=$(wc -c < "${UART_LOG}" 2>/dev/null || echo 0)
log "Captured: ${UART_BYTES} bytes / ${UART_LINES} lines → ${UART_LOG}"

# Echo captured content to script log
log "UART output:"
while IFS= read -r line; do
    log "  ${line}"
done < "${UART_LOG}"

# ---------------------------------------------------------------------------
# Pattern match
# ---------------------------------------------------------------------------
if grep -qP "${UART_EXPECT_PATTERN}" "${UART_LOG}" 2>/dev/null; then
    log "Pattern match: '${UART_EXPECT_PATTERN}' — FOUND"
    log "=== capture_uart PASSED ==="
    exit 0
else
    fail "Pattern '${UART_EXPECT_PATTERN}' not found in UART output from ${SERIAL_PORT}"
fi
