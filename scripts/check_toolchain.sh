#!/usr/bin/env bash
# =============================================================================
# check_toolchain.sh - Verify build toolchain for pico-examples
# =============================================================================
# Environment variables:
#   LOG_DIR   Directory for log files (default: logs)
# =============================================================================
set -euo pipefail

SCRIPT_NAME="$(basename "$0" .sh)"
LOG_DIR="${LOG_DIR:-logs}"
mkdir -p "${LOG_DIR}"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"
ln -sf "$(basename "${LOG_FILE}")" "${LOG_DIR}/${SCRIPT_NAME}.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"; }
fail() { log "ERROR: $*"; exit 1; }

log "=== Toolchain Check ==="
log "Log: ${LOG_FILE}"

# ---------------------------------------------------------------------------
# arm-none-eabi-gcc
# ---------------------------------------------------------------------------
if ! command -v arm-none-eabi-gcc &>/dev/null; then
    fail "arm-none-eabi-gcc not found. Install: sudo apt-get install gcc-arm-none-eabi"
fi
GCC_VER=$(arm-none-eabi-gcc --version | head -1)
log "arm-none-eabi-gcc: ${GCC_VER}"

if ! command -v arm-none-eabi-g++ &>/dev/null; then
    fail "arm-none-eabi-g++ not found. Install: sudo apt-get install gcc-arm-none-eabi"
fi
log "arm-none-eabi-g++: $(arm-none-eabi-g++ --version | head -1)"

if ! command -v arm-none-eabi-objcopy &>/dev/null; then
    fail "arm-none-eabi-objcopy not found. Install: sudo apt-get install binutils-arm-none-eabi"
fi
log "arm-none-eabi-objcopy: $(arm-none-eabi-objcopy --version | head -1)"

# ---------------------------------------------------------------------------
# cmake (must be >= 3.13 for -S/-B flags; SDK requires >= 3.12)
# ---------------------------------------------------------------------------
if ! command -v cmake &>/dev/null; then
    fail "cmake not found. Install: sudo apt-get install cmake"
fi
CMAKE_VER=$(cmake --version | head -1)
log "cmake: ${CMAKE_VER}"

CMAKE_VER_NUM=$(cmake --version | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+')
REQUIRED_CMAKE="3.13"
if ! printf '%s\n' "${REQUIRED_CMAKE}" "${CMAKE_VER_NUM}" | sort -V -C; then
    fail "cmake ${CMAKE_VER_NUM} is too old (>= ${REQUIRED_CMAKE} required)"
fi
log "cmake version OK (>= ${REQUIRED_CMAKE})"

# ---------------------------------------------------------------------------
# python3
# ---------------------------------------------------------------------------
if ! command -v python3 &>/dev/null; then
    fail "python3 not found. Install: sudo apt-get install python3"
fi
log "python3: $(python3 --version)"

# ---------------------------------------------------------------------------
# make / ninja (at least one build driver required)
# ---------------------------------------------------------------------------
if command -v ninja &>/dev/null; then
    log "ninja: $(ninja --version) (will be used if -G Ninja configured)"
elif command -v make &>/dev/null; then
    log "make: $(make --version | head -1)"
else
    fail "Neither ninja nor make found. Install: sudo apt-get install build-essential"
fi

log "=== Toolchain check PASSED ==="
exit 0
