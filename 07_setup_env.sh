#!/usr/bin/env bash
# =============================================================================
# 07_setup_env.sh
# Source this file before running any ArduPilot waf commands.
#
#   source ./07_setup_env.sh
#
# It exports every PATH and variable needed by waf, the cross compiler,
# ccache, and Python.  Add this source line to ~/.bashrc or ~/.profile for
# a persistent environment.
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

# ---- Toolchain binaries (arm-none-eabi-gcc, cmake, ninja, ccache …) --------
export PATH="${AP_PREFIX}/lib/ccache:${AP_PREFIX}/bin:${PATH}"

# ---- pkg-config -------------------------------------------------------------
export PKG_CONFIG_PATH="${AP_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

# ---- Linker / compiler flags so host tools find our libraries ---------------
export CPPFLAGS="-I${AP_PREFIX}/include"
export LDFLAGS="-L${AP_PREFIX}/lib -Wl,-rpath,${AP_PREFIX}/lib"

# ---- ccache settings --------------------------------------------------------
export CCACHE_DIR="${HOME}/.ccache"
export CCACHE_MAXSIZE="10G"
export CCACHE_COMPRESS=1

# ---- ArduPilot / waf --------------------------------------------------------
export ARDUPILOT_HOME="${ARDUPILOT_HOME:-${HOME}/ardupilot}"

# waf finds Python automatically; point it at the right Python explicitly
export WAF_PYTHON=$(command -v python3)

# ---- Verification -----------------------------------------------------------
_check_tool() {
    local label="$1"; local cmd="$2"
    if command -v "${cmd}" &>/dev/null; then
        local ver
        ver=$("${cmd}" --version 2>&1 | head -1)
        echo -e "  \033[0;32m✓\033[0m ${label}: ${ver}"
    else
        echo -e "  \033[0;31m✗\033[0m ${label}: NOT FOUND"
    fi
}

echo ""
echo "ArduPilot / Alpine build environment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
_check_tool "arm-none-eabi-gcc" "arm-none-eabi-gcc"
_check_tool "arm-none-eabi-g++" "arm-none-eabi-g++"
_check_tool "cmake"             "cmake"
_check_tool "ninja"             "ninja"
_check_tool "ccache"            "ccache"
_check_tool "python3"           "python3"
echo ""
echo "  ARDUPILOT_HOME = ${ARDUPILOT_HOME}"
echo "  AP_PREFIX      = ${AP_PREFIX}"
echo ""

# Verify empy version (critical)
python3 -c "
import em, sys
v = tuple(int(x) for x in em.__version__.split('.')[:2])
if v >= (4,0):
    print(f'  \033[0;31m✗\033[0m empy {em.__version__} >= 4.0 — will BREAK waf. Run: pip install \"empy>=3.3,<4\"')
    sys.exit(1)
else:
    print(f'  \033[0;32m✓\033[0m empy {em.__version__} (< 4.0 — OK)')
" 2>/dev/null || true
