#!/usr/bin/env bash
# =============================================================================
# verify_artifact.sh - Verify a built UF2 firmware file with picotool info
# =============================================================================
# Confirms the UF2 is valid RP2040/RP2350 firmware before flashing.
#
# Environment variables:
#   TARGET     CMake target name (e.g. blink, hello_serial) — required
#   BUILD_DIR  CMake build directory (default: build)
#   LOG_DIR    Directory for log files (default: logs)
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"

[ -z "${TARGET}" ] && fail "TARGET env var is required (e.g. TARGET=blink)"

log "=== Verify Artifact: ${TARGET} ==="
log "Build dir : ${BUILD_DIR}"
log "Log       : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Locate UF2
# ---------------------------------------------------------------------------
UF2_FILE=$(find "${BUILD_DIR}" -name "${TARGET}.uf2" 2>/dev/null | head -1 || true)
if [ -z "${UF2_FILE}" ]; then
    fail "${TARGET}.uf2 not found under ${BUILD_DIR} — run the build step first"
fi
log "UF2 file  : ${UF2_FILE} ($(du -h "${UF2_FILE}" | cut -f1))"

# ---------------------------------------------------------------------------
# UF2 magic bytes (0x0A324655 little-endian → 5546320a)
# ---------------------------------------------------------------------------
UF2_MAGIC=$(xxd -l 4 -p "${UF2_FILE}" 2>/dev/null || true)
if [ "${UF2_MAGIC}" = "5546320a" ]; then
    log "  PASS: UF2 magic bytes valid (0x0A324655)"
else
    fail "UF2 magic bytes invalid (got: ${UF2_MAGIC}, expected: 5546320a) — file may be corrupt"
fi

# ---------------------------------------------------------------------------
# picotool info — confirms chip family and program metadata
# ---------------------------------------------------------------------------
if ! command -v picotool &>/dev/null; then
    fail "picotool not found — install from https://github.com/raspberrypi/picotool"
fi

log "Running: picotool info ${UF2_FILE}"
PTOOL_OUT=$(picotool info "${UF2_FILE}" 2>&1 || true)
while IFS= read -r line; do
    log "  ${line}"
done <<< "${PTOOL_OUT}"

if echo "${PTOOL_OUT}" | grep -qi 'rp2040\|rp2350'; then
    CHIP=$(echo "${PTOOL_OUT}" | grep -oi 'rp2040\|rp2350' | head -1 | tr '[:lower:]' '[:upper:]')
    log "Chip family confirmed: ${CHIP}"
else
    fail "picotool info did not confirm RP2040/RP2350 chip family in output"
fi

log "=== verify_artifact PASSED ==="
exit 0
