#!/usr/bin/env bash
# =============================================================================
# cmake_configure.sh - Configure cmake build for pico-examples
# =============================================================================
# Environment variables:
#   PICO_SDK_PATH     Path to pico-sdk (required)
#   PICO_BOARD        Target board (default: pico)
#   PICO_PLATFORM     Target platform (default: rp2040)
#   BUILD_TYPE        CMake build type (default: Release)
#   BUILD_DIR         Build output directory (default: build)
#   WIFI_SSID         Optional: compile-time Wi-Fi SSID
#   WIFI_PASSWORD     Optional: compile-time Wi-Fi password
#   FREERTOS_KERNEL_PATH  Optional: path to FreeRTOS kernel
#   PICO_TOOLCHAIN_PATH   Optional: path to alternate toolchain
#   PICO_COMPILER         Optional: e.g. pico_arm_clang
#   EXTRA_CMAKE_ARGS      Optional: additional -D flags (space-separated)
#   LOG_DIR           Directory for log files (default: logs)
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
# Resolve configuration — locate project root relative to this script
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PICO_SDK_PATH="${PICO_SDK_PATH:-}"
PICO_BOARD="${PICO_BOARD:-pico}"
PICO_PLATFORM="${PICO_PLATFORM:-rp2040}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PASSWORD="${WIFI_PASSWORD:-}"
FREERTOS_KERNEL_PATH="${FREERTOS_KERNEL_PATH:-}"
PICO_TOOLCHAIN_PATH="${PICO_TOOLCHAIN_PATH:-}"
PICO_COMPILER="${PICO_COMPILER:-}"
EXTRA_CMAKE_ARGS="${EXTRA_CMAKE_ARGS:-}"

log "=== CMake Configure ==="
log "Project root  : ${PROJECT_ROOT}"
log "Build dir     : ${BUILD_DIR}"
log "PICO_SDK_PATH : ${PICO_SDK_PATH:-<not set>}"
log "PICO_BOARD    : ${PICO_BOARD}"
log "PICO_PLATFORM : ${PICO_PLATFORM}"
log "BUILD_TYPE    : ${BUILD_TYPE}"
log "Log           : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Validate required inputs
# ---------------------------------------------------------------------------
if [ -z "${PICO_SDK_PATH}" ]; then
    # Try common local locations before failing
    for candidate in \
        "${PROJECT_ROOT}/../pico-sdk" \
        "${HOME}/pico/pico-sdk" \
        "${HOME}/pico-sdk"
    do
        if [ -f "${candidate}/pico_sdk_init.cmake" ]; then
            PICO_SDK_PATH="$(cd "${candidate}" && pwd)"
            log "Auto-detected PICO_SDK_PATH=${PICO_SDK_PATH}"
            break
        fi
    done
fi

if [ -z "${PICO_SDK_PATH}" ]; then
    fail "PICO_SDK_PATH is not set and SDK not found at common locations. Run setup_sdk.sh first."
fi

if [ ! -f "${PICO_SDK_PATH}/pico_sdk_init.cmake" ]; then
    fail "PICO_SDK_PATH='${PICO_SDK_PATH}' does not contain pico_sdk_init.cmake"
fi

# ---------------------------------------------------------------------------
# Build cmake argument list
# ---------------------------------------------------------------------------
CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
    -DPICO_BOARD="${PICO_BOARD}"
    -DPICO_PLATFORM="${PICO_PLATFORM}"
)

[ -n "${WIFI_SSID}" ]             && CMAKE_ARGS+=(-DWIFI_SSID="${WIFI_SSID}")
[ -n "${WIFI_PASSWORD}" ]         && CMAKE_ARGS+=(-DWIFI_PASSWORD="${WIFI_PASSWORD}")
[ -n "${FREERTOS_KERNEL_PATH}" ]  && CMAKE_ARGS+=(-DFREERTOS_KERNEL_PATH="${FREERTOS_KERNEL_PATH}")
[ -n "${PICO_TOOLCHAIN_PATH}" ]   && CMAKE_ARGS+=(-DPICO_TOOLCHAIN_PATH="${PICO_TOOLCHAIN_PATH}")
[ -n "${PICO_COMPILER}" ]         && CMAKE_ARGS+=(-DPICO_COMPILER="${PICO_COMPILER}")

# Append any caller-supplied extra flags (word-split intentional)
if [ -n "${EXTRA_CMAKE_ARGS}" ]; then
    # shellcheck disable=SC2206
    CMAKE_ARGS+=(${EXTRA_CMAKE_ARGS})
fi

# ---------------------------------------------------------------------------
# Check if already configured with the same settings (idempotent)
# ---------------------------------------------------------------------------
CMAKE_CACHE="${BUILD_DIR}/CMakeCache.txt"
NEEDS_CONFIGURE=true

if [ -f "${CMAKE_CACHE}" ]; then
    CACHED_BOARD=$(grep -oP '(?<=PICO_BOARD:STRING=)\S+' "${CMAKE_CACHE}" 2>/dev/null || true)
    CACHED_PLATFORM=$(grep -oP '(?<=PICO_PLATFORM:STRING=)\S+' "${CMAKE_CACHE}" 2>/dev/null || true)
    CACHED_TYPE=$(grep -oP '(?<=CMAKE_BUILD_TYPE:STRING=)\S+' "${CMAKE_CACHE}" 2>/dev/null || true)
    if [ "${CACHED_BOARD}" = "${PICO_BOARD}" ] && \
       [ "${CACHED_PLATFORM}" = "${PICO_PLATFORM}" ] && \
       [ "${CACHED_TYPE}" = "${BUILD_TYPE}" ]; then
        log "CMakeCache already configured for board=${PICO_BOARD} platform=${PICO_PLATFORM} type=${BUILD_TYPE} — skipping re-configure."
        NEEDS_CONFIGURE=false
    else
        log "Cached settings differ (board=${CACHED_BOARD} platform=${CACHED_PLATFORM} type=${CACHED_TYPE}) — reconfiguring."
    fi
fi

if ${NEEDS_CONFIGURE}; then
    mkdir -p "${BUILD_DIR}"
    log "Running: PICO_SDK_PATH=${PICO_SDK_PATH} cmake -S ${PROJECT_ROOT} -B ${BUILD_DIR} ${CMAKE_ARGS[*]}"
    PICO_SDK_PATH="${PICO_SDK_PATH}" cmake \
        -S "${PROJECT_ROOT}" \
        -B "${BUILD_DIR}" \
        "${CMAKE_ARGS[@]}" \
        2>&1 | tee -a "${LOG_FILE}"
fi

log "=== CMake configure PASSED ==="
exit 0
