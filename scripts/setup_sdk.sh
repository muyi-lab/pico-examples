#!/usr/bin/env bash
# =============================================================================
# setup_sdk.sh - Clone and initialise pico-sdk
# =============================================================================
# Environment variables:
#   PICO_SDK_PATH   Where the SDK lives (default: $HOME/pico/pico-sdk)
#   PICO_SDK_GIT    Repository URL (default: upstream GitHub URL)
#   PICO_SDK_REF    Branch / tag to checkout (default: master)
#   LOG_DIR         Directory for log files (default: logs)
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

PICO_SDK_PATH="${PICO_SDK_PATH:-${HOME}/pico/pico-sdk}"
PICO_SDK_GIT="${PICO_SDK_GIT:-https://github.com/raspberrypi/pico-sdk.git}"
PICO_SDK_REF="${PICO_SDK_REF:-master}"

log "=== SDK Setup ==="
log "Target path : ${PICO_SDK_PATH}"
log "Repository  : ${PICO_SDK_GIT}"
log "Ref         : ${PICO_SDK_REF}"
log "Log         : ${LOG_FILE}"

# ---------------------------------------------------------------------------
# Clone if not present
# ---------------------------------------------------------------------------
if [ ! -d "${PICO_SDK_PATH}" ]; then
    log "SDK directory not found — cloning..."
    mkdir -p "$(dirname "${PICO_SDK_PATH}")"
    git clone --branch "${PICO_SDK_REF}" "${PICO_SDK_GIT}" "${PICO_SDK_PATH}" \
        2>&1 | tee -a "${LOG_FILE}"
    log "Clone complete."
else
    log "SDK directory already exists — skipping clone."
fi

# ---------------------------------------------------------------------------
# Validate it looks like the Pico SDK
# ---------------------------------------------------------------------------
if [ ! -f "${PICO_SDK_PATH}/pico_sdk_init.cmake" ]; then
    fail "'${PICO_SDK_PATH}' does not look like a pico-sdk checkout (pico_sdk_init.cmake missing)"
fi

# ---------------------------------------------------------------------------
# Initialise / update submodules (idempotent)
# ---------------------------------------------------------------------------
SUBMODULE_SENTINEL="${PICO_SDK_PATH}/lib/tinyusb/src/tusb.h"
if [ ! -f "${SUBMODULE_SENTINEL}" ]; then
    log "Initialising SDK submodules..."
    git -C "${PICO_SDK_PATH}" submodule update --init 2>&1 | tee -a "${LOG_FILE}"
    log "Submodule init complete."
else
    log "Submodules already initialised — skipping."
fi

# ---------------------------------------------------------------------------
# Export for downstream scripts
# ---------------------------------------------------------------------------
log "export PICO_SDK_PATH=${PICO_SDK_PATH}"
log "=== SDK setup PASSED ==="
exit 0
