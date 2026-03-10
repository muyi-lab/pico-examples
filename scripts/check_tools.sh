#!/bin/bash
# =============================================================================
# check_env.sh - Environment Verification for pico-examples Workflow System
# =============================================================================
# Run this ONCE before your first Claude Code session.
# It checks all prerequisites and optionally installs missing packages.
#
# Usage:
#   bash check_env.sh              # Check only (no changes)
#   bash check_env.sh --install    # Check + install missing packages (apt)
#   bash check_env.sh --verbose    # Show detailed version info
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REQUIRED_CMAKE_VERSION="3.13"
REQUIRED_PYTHON_VERSION="3.8"
PICO_SDK_REPO="https://github.com/raspberrypi/pico-sdk.git"

# ---------------------------------------------------------------------------
# Color output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DO_INSTALL=false
VERBOSE=false
for arg in "$@"; do
    case "$arg" in
        --install)  DO_INSTALL=true ;;
        --verbose)  VERBOSE=true ;;
        --help|-h)
            echo "Usage: bash check_env.sh [--install] [--verbose]"
            echo "  --install   Attempt to install missing packages via apt"
            echo "  --verbose   Show detailed version and path information"
            exit 0
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
WARN=0

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
pass() {
    echo -e "  ${GREEN}✔${NC} $1"
    ((PASS++))
}

fail() {
    echo -e "  ${RED}✘${NC} $1"
    ((FAIL++))
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    ((WARN++))
}

info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

section() {
    echo ""
    echo -e "${BOLD}${CYAN}[$1]${NC}"
}

# Compare two version strings: returns 0 if $1 >= $2
version_ge() {
    # Use sort -V to compare versions
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

# Try to install a package via apt
try_install() {
    local pkg="$1"
    if $DO_INSTALL; then
        echo -e "  ${YELLOW}→${NC} Attempting: sudo apt-get install -y $pkg"
        if sudo apt-get install -y "$pkg" > /dev/null 2>&1; then
            echo -e "  ${GREEN}→${NC} Successfully installed $pkg"
            return 0
        else
            echo -e "  ${RED}→${NC} Failed to install $pkg"
            return 1
        fi
    else
        info "Run with --install to attempt automatic installation"
        info "Or manually: sudo apt-get install $pkg"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}=================================================================${NC}"
echo -e "${BOLD}  pico-examples Workflow System - Environment Check${NC}"
echo -e "${BOLD}=================================================================${NC}"
echo -e "  Date:     $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "  Host:     $(hostname)"
echo -e "  OS:       $(lsb_release -ds 2>/dev/null || uname -s)"
echo -e "  Arch:     $(uname -m)"
echo -e "${BOLD}=================================================================${NC}"

# ===========================================================================
# 1. ARM Cross-Compilation Toolchain
# ===========================================================================
section "ARM Cross-Compilation Toolchain"

if command -v arm-none-eabi-gcc &> /dev/null; then
    GCC_VERSION=$(arm-none-eabi-gcc --version | head -1)
    pass "arm-none-eabi-gcc found"
    $VERBOSE && info "Version: $GCC_VERSION"
    $VERBOSE && info "Path:    $(which arm-none-eabi-gcc)"
else
    fail "arm-none-eabi-gcc not found"
    try_install "gcc-arm-none-eabi"
fi

if command -v arm-none-eabi-g++ &> /dev/null; then
    pass "arm-none-eabi-g++ found"
else
    fail "arm-none-eabi-g++ not found"
    try_install "gcc-arm-none-eabi"
fi

if command -v arm-none-eabi-objcopy &> /dev/null; then
    pass "arm-none-eabi-objcopy found (needed for .uf2 generation)"
else
    fail "arm-none-eabi-objcopy not found"
    try_install "binutils-arm-none-eabi"
fi

# Check for newlib (required by pico-sdk)
if dpkg -l libnewlib-arm-none-eabi &> /dev/null 2>&1; then
    pass "libnewlib-arm-none-eabi installed"
elif [ -f /usr/lib/arm-none-eabi/lib/libc.a ]; then
    pass "newlib detected (non-dpkg install)"
else
    fail "libnewlib-arm-none-eabi not found"
    try_install "libnewlib-arm-none-eabi"
fi

if dpkg -l libstdc++-arm-none-eabi-newlib &> /dev/null 2>&1; then
    pass "libstdc++-arm-none-eabi-newlib installed"
else
    warn "libstdc++-arm-none-eabi-newlib not found (needed for C++ examples)"
    $DO_INSTALL && try_install "libstdc++-arm-none-eabi-newlib"
fi

# ===========================================================================
# 2. Build Tools
# ===========================================================================
section "Build Tools"

# CMake
if command -v cmake &> /dev/null; then
    CMAKE_VERSION=$(cmake --version | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+')
    if version_ge "$CMAKE_VERSION" "$REQUIRED_CMAKE_VERSION"; then
        pass "cmake $CMAKE_VERSION (>= $REQUIRED_CMAKE_VERSION required)"
    else
        fail "cmake $CMAKE_VERSION is too old (>= $REQUIRED_CMAKE_VERSION required)"
    fi
    $VERBOSE && info "Path: $(which cmake)"
else
    fail "cmake not found"
    try_install "cmake"
fi

# Make or Ninja
if command -v make &> /dev/null; then
    pass "make found ($(make --version | head -1))"
else
    fail "make not found"
    try_install "build-essential"
fi

if command -v ninja &> /dev/null; then
    pass "ninja found (optional, faster builds)"
    $VERBOSE && info "Use: cmake -G Ninja .. to enable"
else
    warn "ninja not found (optional but recommended for faster builds)"
    $DO_INSTALL && try_install "ninja-build"
fi

# ===========================================================================
# 3. Python (for workflow runner)
# ===========================================================================
section "Python Environment"

if command -v python3 &> /dev/null; then
    PY_VERSION=$(python3 --version 2>&1 | grep -oP '[\d]+\.[\d]+\.[\d]+')
    if version_ge "$PY_VERSION" "$REQUIRED_PYTHON_VERSION"; then
        pass "python3 $PY_VERSION (>= $REQUIRED_PYTHON_VERSION required)"
    else
        fail "python3 $PY_VERSION is too old (>= $REQUIRED_PYTHON_VERSION required)"
    fi
    $VERBOSE && info "Path: $(which python3)"
else
    fail "python3 not found"
    try_install "python3"
fi

# Check PyYAML
if python3 -c "import yaml" 2>/dev/null; then
    PYYAML_VERSION=$(python3 -c "import yaml; print(yaml.__version__)" 2>/dev/null)
    pass "PyYAML $PYYAML_VERSION installed"
else
    fail "PyYAML not installed (required by workflow runner)"
    info "Install: pip3 install pyyaml"
    if $DO_INSTALL; then
        echo -e "  ${YELLOW}→${NC} Attempting: pip3 install pyyaml"
        if pip3 install pyyaml --break-system-packages 2>/dev/null || \
           pip3 install pyyaml 2>/dev/null; then
            echo -e "  ${GREEN}→${NC} Successfully installed PyYAML"
        else
            echo -e "  ${RED}→${NC} Failed. Try: pip3 install --user pyyaml"
        fi
    fi
fi

# ===========================================================================
# 4. Git
# ===========================================================================
section "Git"

if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version | grep -oP '[\d]+\.[\d]+\.[\d]+')
    pass "git $GIT_VERSION"
    $VERBOSE && info "Path: $(which git)"
else
    fail "git not found"
    try_install "git"
fi

# ===========================================================================
# 5. Utilities (for Claude Code hooks)
# ===========================================================================
section "Utilities (for hooks and scripts)"

if command -v jq &> /dev/null; then
    pass "jq found (needed by Claude Code hooks to parse JSON)"
    $VERBOSE && info "Version: $(jq --version)"
else
    fail "jq not found (Claude Code hooks need this to parse JSON events)"
    try_install "jq"
fi

if command -v tee &> /dev/null; then
    pass "tee found"
else
    warn "tee not found (used for logging)"
fi

if command -v grep &> /dev/null; then
    GREP_SUPPORTS_P=false
    echo "test" | grep -P "test" &>/dev/null && GREP_SUPPORTS_P=true
    pass "grep found"
    if $GREP_SUPPORTS_P; then
        pass "grep supports -P (Perl regex)"
    else
        warn "grep does not support -P flag, some log parsing may be limited"
    fi
else
    fail "grep not found"
fi

# ===========================================================================
# 6. Pico SDK
# ===========================================================================
section "Pico SDK"

SDK_FOUND=false

# Check PICO_SDK_PATH env var first
if [ -n "${PICO_SDK_PATH:-}" ]; then
    if [ -f "$PICO_SDK_PATH/CMakeLists.txt" ]; then
        pass "PICO_SDK_PATH is set and valid: $PICO_SDK_PATH"
        SDK_FOUND=true
        # Check submodules
        if [ -f "$PICO_SDK_PATH/lib/tinyusb/src/tusb.h" ]; then
            pass "SDK submodules initialized"
        else
            warn "SDK submodules may not be initialized"
            info "Run: cd $PICO_SDK_PATH && git submodule update --init"
        fi
    else
        fail "PICO_SDK_PATH is set ($PICO_SDK_PATH) but does not contain CMakeLists.txt"
    fi
else
    warn "PICO_SDK_PATH not set"
fi

# Check common local locations
if ! $SDK_FOUND; then
    for candidate in "./pico-sdk" "../pico-sdk" "$HOME/pico-sdk" "$HOME/pico/pico-sdk"; do
        if [ -f "$candidate/CMakeLists.txt" ]; then
            SDK_PATH_FOUND=$(cd "$candidate" && pwd)
            warn "Found SDK at $SDK_PATH_FOUND but PICO_SDK_PATH not set"
            info "Run: export PICO_SDK_PATH=$SDK_PATH_FOUND"
            SDK_FOUND=true
            break
        fi
    done
fi

if ! $SDK_FOUND; then
    fail "Pico SDK not found anywhere"
    info "Clone it: git clone $PICO_SDK_REPO"
    info "Then: cd pico-sdk && git submodule update --init"
    info "Then: export PICO_SDK_PATH=\$(pwd)"
fi

# ===========================================================================
# 7. Disk Space
# ===========================================================================
section "Disk Space"

AVAIL_MB=$(df -BM . 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'M')
if [ -n "$AVAIL_MB" ] && [ "$AVAIL_MB" -gt 2000 ]; then
    pass "Available disk space: ${AVAIL_MB}MB (>2GB, enough for full build)"
elif [ -n "$AVAIL_MB" ] && [ "$AVAIL_MB" -gt 500 ]; then
    warn "Available disk space: ${AVAIL_MB}MB (low, full build needs ~2GB)"
else
    fail "Available disk space may be insufficient: ${AVAIL_MB:-unknown}MB"
fi

# ===========================================================================
# 8. Claude Code (optional check)
# ===========================================================================
section "Claude Code"

if command -v claude &> /dev/null; then
    CLAUDE_VERSION=$(claude --version 2>/dev/null || echo "unknown")
    pass "Claude Code installed: $CLAUDE_VERSION"
else
    warn "Claude Code not detected in PATH"
    info "Install: npm install -g @anthropic-ai/claude-code"
fi

# Check if Node.js is available (required for Claude Code)
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    pass "Node.js $NODE_VERSION (needed by Claude Code)"
else
    warn "Node.js not found (required for Claude Code)"
    info "Install: https://nodejs.org/ or via nvm"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo -e "${BOLD}=================================================================${NC}"
echo -e "${BOLD}  Summary${NC}"
echo -e "${BOLD}=================================================================${NC}"
echo -e "  ${GREEN}✔ Passed:${NC}  $PASS"
echo -e "  ${YELLOW}⚠ Warnings:${NC} $WARN"
echo -e "  ${RED}✘ Failed:${NC}  $FAIL"
echo ""

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}🎉 All checks passed! Ready to start Claude Code.${NC}"
    echo ""
    echo -e "  Next steps:"
    echo -e "    cd $(pwd)"
    echo -e "    claude"
    echo ""
elif [ "$FAIL" -eq 0 ]; then
    echo -e "  ${YELLOW}${BOLD}⚠ All required tools present, but check the warnings above.${NC}"
    echo ""
    echo -e "  You can proceed, but consider fixing the warnings first."
    echo -e "  Next steps:"
    echo -e "    cd $(pwd)"
    echo -e "    claude"
    echo ""
else
    echo -e "  ${RED}${BOLD}✘ $FAIL required check(s) failed. Fix them before proceeding.${NC}"
    echo ""
    if ! $DO_INSTALL; then
        echo -e "  Quick fix attempt:"
        echo -e "    bash $0 --install"
        echo ""
    fi
    echo -e "  Manual install (Ubuntu/Debian):"
    echo -e "    sudo apt-get update"
    echo -e "    sudo apt-get install -y \\"
    echo -e "      gcc-arm-none-eabi libnewlib-arm-none-eabi \\"
    echo -e "      libstdc++-arm-none-eabi-newlib \\"
    echo -e "      cmake build-essential git jq python3 python3-pip"
    echo -e "    pip3 install pyyaml"
    echo ""
fi

# Exit with appropriate code
if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
