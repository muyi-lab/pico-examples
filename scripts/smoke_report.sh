#!/usr/bin/env bash
# =============================================================================
# smoke_report.sh - Collect smoke test results into a JSON report
# =============================================================================
# Reads per-step log files (via stable symlinks) and workflow_state.json,
# then writes smoke_test_report_<timestamp>.json to LOG_DIR with a stable
# smoke_test_report.json symlink.
#
# Environment variables:
#   TARGET               CMake target that was tested — required
#   PICO_BOARD           Board name (default: pico)
#   PICO_PLATFORM        Platform (default: rp2040)
#   FLASH_METHOD         Flash method used (default: picotool)
#   UART_EXPECT_PATTERN  Pattern that was verified (default: "")
#   LOG_DIR              Directory for log files (default: logs)
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
PICO_BOARD="${PICO_BOARD:-pico}"
PICO_PLATFORM="${PICO_PLATFORM:-rp2040}"
FLASH_METHOD="${FLASH_METHOD:-picotool}"
UART_EXPECT_PATTERN="${UART_EXPECT_PATTERN:-}"

[ -z "${TARGET}" ] && fail "TARGET env var is required"

TARGET_SAFE="${TARGET//\//_}"
REPORT_FILE="${LOG_DIR}/smoke_test_report_${TIMESTAMP}.json"
REPORT_LATEST="${LOG_DIR}/smoke_test_report.json"

log "=== Smoke Test Report ==="
log "Target          : ${TARGET}"
log "Board           : ${PICO_BOARD} / ${PICO_PLATFORM}"
log "Flash method    : ${FLASH_METHOD}"
log "Expect pattern  : '${UART_EXPECT_PATTERN}'"
log "Report file     : ${REPORT_FILE}"
log "Log             : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Determine pass/fail/skipped/not_run for a step from its log symlink.
step_status() {
    local log_path="$1"

    if [ ! -f "${log_path}" ]; then
        echo "not_run"
        return
    fi

    if grep -qP 'PASSED \(skip' "${log_path}" 2>/dev/null; then
        echo "skipped"
        return
    fi

    if grep -qP '(PASSED|COMPLETE)\s*===' "${log_path}" 2>/dev/null; then
        echo "passed"
        return
    fi

    if grep -q '] ERROR:' "${log_path}" 2>/dev/null; then
        echo "failed"
        return
    fi

    echo "unknown"
}

# Extract first grep match from a log file (best-effort, returns "" if missing).
log_detail() {
    local log_path="$1"
    local pattern="$2"
    [ -f "${log_path}" ] && grep -oP "${pattern}" "${log_path}" 2>/dev/null | head -1 || true
}

# JSON-escape a string (backslash and double-quote).
json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "${s}"
}

# ---------------------------------------------------------------------------
# Collect step statuses from log symlinks
# ---------------------------------------------------------------------------
# Build step is run via nested workflow_runner — check its state file
BUILD_STATUS="not_run"
BUILD_STATE="${LOG_DIR}/build_example_state.json"
if [ -f "${BUILD_STATE}" ]; then
    if grep -q '"status": "completed"' "${BUILD_STATE}" 2>/dev/null; then
        # All steps completed = build passed
        if ! grep -q '"status": "failed"' "${BUILD_STATE}" 2>/dev/null; then
            BUILD_STATUS="passed"
        else
            BUILD_STATUS="failed"
        fi
    elif grep -q '"status": "failed"' "${BUILD_STATE}" 2>/dev/null; then
        BUILD_STATUS="failed"
    fi
fi
ARTIFACT_STATUS=$(step_status "${LOG_DIR}/verify_artifact.log")
BOOTSEL_STATUS=$(step_status  "${LOG_DIR}/reboot_bootsel.log")
FLASH_STATUS=$(step_status    "${LOG_DIR}/flash_firmware.log")
UART_STATUS=$(step_status     "${LOG_DIR}/capture_uart.log")

log "Step results:"
log "  build           : ${BUILD_STATUS}"
log "  verify_artifact : ${ARTIFACT_STATUS}"
log "  reboot_bootsel  : ${BOOTSEL_STATUS}"
log "  flash_firmware  : ${FLASH_STATUS}"
log "  capture_uart    : ${UART_STATUS}"

# ---------------------------------------------------------------------------
# Extra details (best-effort)
# ---------------------------------------------------------------------------
CHIP_FAMILY=$(log_detail "${LOG_DIR}/verify_artifact.log" '(?<=Chip family confirmed: )\S+')
UF2_FILE=$(log_detail    "${LOG_DIR}/verify_artifact.log" '(?<=UF2 file  : ).+')
UART_PATTERN_RESULT=$(log_detail "${LOG_DIR}/capture_uart.log" "(?<=Pattern match: ').+" || true)

# Pull UART snippet (first non-empty line captured)
UART_SAMPLE=""
UART_LOG="${LOG_DIR}/uart_${TARGET_SAFE}.log"
if [ -f "${UART_LOG}" ]; then
    UART_SAMPLE=$(grep -m1 -v '^$\|SKIPPED' "${UART_LOG}" 2>/dev/null | tr -d '\r' || true)
fi

# ---------------------------------------------------------------------------
# Determine overall status
# ---------------------------------------------------------------------------
OVERALL="passed"
for STATUS in "${BUILD_STATUS}" "${ARTIFACT_STATUS}" "${BOOTSEL_STATUS}" "${FLASH_STATUS}" "${UART_STATUS}"; do
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
  "timestamp":    "$(json_str "${ISO_TS}")",
  "target":       "$(json_str "${TARGET}")",
  "board":        "$(json_str "${PICO_BOARD}")",
  "platform":     "$(json_str "${PICO_PLATFORM}")",
  "flash_method": "$(json_str "${FLASH_METHOD}")",
  "steps": {
    "build":           "$(json_str "${BUILD_STATUS}")",
    "verify_artifact": "$(json_str "${ARTIFACT_STATUS}")",
    "reboot_bootsel":  "$(json_str "${BOOTSEL_STATUS}")",
    "flash_firmware":  "$(json_str "${FLASH_STATUS}")",
    "capture_uart":    "$(json_str "${UART_STATUS}")"
  },
  "details": {
    "chip_family":        "$(json_str "${CHIP_FAMILY}")",
    "uf2_file":           "$(json_str "${UF2_FILE}")",
    "uart_expect_pattern":"$(json_str "${UART_EXPECT_PATTERN}")",
    "uart_pattern_result":"$(json_str "${UART_PATTERN_RESULT}")",
    "uart_sample":        "$(json_str "${UART_SAMPLE}")"
  },
  "overall": "$(json_str "${OVERALL}")"
}
EOF

ln -sf "$(basename "${REPORT_FILE}")" "${REPORT_LATEST}"

log "Report written  → ${REPORT_FILE}"
log "Symlink updated → ${REPORT_LATEST}"
log "=== smoke_report PASSED ==="
exit 0
