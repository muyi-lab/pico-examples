#!/usr/bin/env bash
# =============================================================================
# verify_output.sh - Verify build output for a pico-examples target
# =============================================================================
# Usage:
#   verify_output.sh <target_name>
#
# Environment variables:
#   BUILD_DIR   CMake build directory (default: build)
#   LOG_DIR     Directory for log files (default: logs)
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed
# =============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0" .sh)"
LOG_DIR="${LOG_DIR:-logs}"
mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"
ln -sf "$(basename "${LOG_FILE}")" "${LOG_DIR}/${SCRIPT_NAME}.log"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
pass() { log "  PASS: $*"; }
fail() { log "  FAIL: $*"; FAILURES=$((FAILURES + 1)); }

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
if [ $# -lt 1 ]; then
    log "ERROR: Usage: $(basename "$0") <target_name>"
    exit 1
fi
TARGET="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
FAILURES=0

log "=== Verify Output: ${TARGET} ==="
log "Build dir : ${BUILD_DIR}"
log "Log       : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Locate target artifacts by searching the whole build tree.
# Targets may live in subdirs whose name differs from the cmake target name
# (e.g. target "hello_serial" lives in build/hello_world/serial/).
# ---------------------------------------------------------------------------
UF2_FILE=$(find "${BUILD_DIR}" -name "${TARGET}.uf2" 2>/dev/null | head -1 || true)
ELF_FILE=$(find "${BUILD_DIR}" -name "${TARGET}.elf" 2>/dev/null | head -1 || true)
BIN_FILE=$(find "${BUILD_DIR}" -name "${TARGET}.bin" 2>/dev/null | head -1 || true)

ARTIFACT_DIR="$(dirname "${ELF_FILE:-${BUILD_DIR}/${TARGET}.elf}")"
log "Artifact search path: ${BUILD_DIR} (found in: ${ARTIFACT_DIR})"

# ---------------------------------------------------------------------------
# Check 1: .uf2 file exists and is non-empty
# ---------------------------------------------------------------------------
if [ -n "${UF2_FILE}" ] && [ -s "${UF2_FILE}" ]; then
    UF2_SIZE=$(du -h "${UF2_FILE}" | cut -f1)
    pass ".uf2 exists: ${UF2_FILE} (${UF2_SIZE})"
else
    fail ".uf2 not found or empty (searched ${BUILD_DIR}/${TARGET}.uf2)"
fi

# ---------------------------------------------------------------------------
# Check 2: .elf file exists and is non-empty
# ---------------------------------------------------------------------------
if [ -n "${ELF_FILE}" ] && [ -s "${ELF_FILE}" ]; then
    ELF_SIZE=$(du -h "${ELF_FILE}" | cut -f1)
    pass ".elf exists: ${ELF_FILE} (${ELF_SIZE})"
    # Also verify it is a valid ARM ELF
    if command -v arm-none-eabi-readelf &>/dev/null; then
        if arm-none-eabi-readelf -h "${ELF_FILE}" &>/dev/null; then
            pass ".elf is a valid ELF binary"
        else
            fail ".elf failed arm-none-eabi-readelf validation"
        fi
    fi
else
    fail ".elf not found or empty (searched ${BUILD_DIR}/${TARGET}.elf)"
fi

# ---------------------------------------------------------------------------
# Check 3: .bin exists (produced by pico_add_extra_outputs)
# ---------------------------------------------------------------------------
if [ -n "${BIN_FILE}" ] && [ -s "${BIN_FILE}" ]; then
    pass ".bin exists: ${BIN_FILE}"
else
    fail ".bin not found or empty (searched ${BUILD_DIR}/${TARGET}.bin)"
fi

# ---------------------------------------------------------------------------
# Check 4: Scan build log for error patterns
# ---------------------------------------------------------------------------
BUILD_LOG="${LOG_DIR}/build_target.log"
if [ -f "${BUILD_LOG}" ]; then
    log "Scanning build log: ${BUILD_LOG}"

    # Fatal cmake/SDK errors
    if grep -qiP '(FATAL_ERROR|fatal error:|undefined reference to|collect2: error|cannot find -l)' "${BUILD_LOG}" 2>/dev/null; then
        MATCHED=$(grep -iP '(FATAL_ERROR|fatal error:|undefined reference to|collect2: error|cannot find -l)' "${BUILD_LOG}" | head -5)
        fail "Error patterns found in build log:\n${MATCHED}"
    else
        pass "No fatal error patterns in build log"
    fi

    # Confirm target was linked (Linking ... <target>.elf)
    if grep -qP "Linking\s+(C|CXX)\s+executable\s+${TARGET}\.elf" "${BUILD_LOG}" 2>/dev/null; then
        pass "Link step confirmed in build log"
    else
        # Not a hard failure — target may have been cached
        log "  INFO: Link step not found in log (may be a cached build)"
    fi
else
    log "  INFO: Build log not found at ${BUILD_LOG} — skipping log scan"
fi

# ---------------------------------------------------------------------------
# Check 5: UF2 magic bytes
# UF2 first magic word is 0x0A324655. Stored little-endian on disk:
# bytes 0x55 0x46 0x32 0x0A → xxd -p output: "5546320a"
# ---------------------------------------------------------------------------
if [ -n "${UF2_FILE}" ] && [ -s "${UF2_FILE}" ]; then
    UF2_MAGIC=$(xxd -l 4 -p "${UF2_FILE}" 2>/dev/null || true)
    if [ "${UF2_MAGIC}" = "5546320a" ]; then
        pass "UF2 magic bytes valid (0x0A324655 little-endian)"
    else
        fail "UF2 magic bytes invalid (got: ${UF2_MAGIC}, expected: 5546320a) — file may be corrupt"
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "" | tee -a "${LOG_FILE}"
if [ "${FAILURES}" -eq 0 ]; then
    log "=== Verify PASSED: ${TARGET} (all checks OK) ==="
    exit 0
else
    log "=== Verify FAILED: ${TARGET} (${FAILURES} check(s) failed) ==="
    exit 1
fi
