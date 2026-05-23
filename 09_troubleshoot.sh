#!/usr/bin/env bash
# =============================================================================
# 09_troubleshoot.sh
# Diagnostics and fixups for common issues when building ArduPilot on Alpine.
#
# Run interactively to diagnose a broken build:
#   bash 09_troubleshoot.sh
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/07_setup_env.sh" 2>/dev/null || true

section "09  Troubleshoot / Diagnostics"

PASS=0; FAIL=0
check() {
    local label="$1"; local cmd="$2"
    if eval "${cmd}" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC}  ${label}"
        PASS=$((PASS+1))
    else
        echo -e "  ${RED}✗${NC}  ${label}"
        FAIL=$((FAIL+1))
    fi
}

# ── Host toolchain ────────────────────────────────────────────────────────────
echo ""; echo "Host toolchain:"
check "gcc (host)"          "command -v gcc"
check "g++ (host)"          "command -v g++"
check "make"                "command -v make"
check "gawk"                "command -v gawk"
check "bison"               "command -v bison"
check "flex"                "command -v flex"
check "patch"               "command -v patch"
check "git"                 "command -v git"
check "wget"                "command -v wget"

# ── From-source tools ─────────────────────────────────────────────────────────
echo ""; echo "From-source tools:"
check "arm-none-eabi-gcc"   "command -v arm-none-eabi-gcc"
check "arm-none-eabi-g++"   "command -v arm-none-eabi-g++"
check "arm-none-eabi-ar"    "command -v arm-none-eabi-ar"
check "arm-none-eabi-objcopy" "command -v arm-none-eabi-objcopy"
check "cmake >= 3.20"       "cmake --version | grep -qE 'cmake version ([3-9][.]([2-9][0-9]|[2-9])\.|[4-9])'"
check "ninja"               "command -v ninja"
check "ccache"              "command -v ccache"

# ── Python packages ───────────────────────────────────────────────────────────
echo ""; echo "Python packages:"
check "python3"             "command -v python3"
check "empy installed"      "python3 -c 'import em'"
check "empy < 4.0"          "python3 -c 'import em; v=tuple(int(x) for x in em.__version__.split(\".\")[:2]); assert v < (4,0)'"
check "future"              "python3 -c 'import future'"
check "pyserial"            "python3 -c 'import serial'"
check "pexpect"             "python3 -c 'import pexpect'"
check "pymavlink"           "python3 -c 'import pymavlink'"
check "lxml"                "python3 -c 'import lxml'"

# ── ArduPilot repo ────────────────────────────────────────────────────────────
echo ""; echo "ArduPilot repository:"
check "ardupilot dir exists"   "[[ -d '${ARDUPILOT_HOME}' ]]"
check "waf script present"     "[[ -f '${ARDUPILOT_HOME}/waf' ]]"
check "submodule: modules/waf" "[[ -d '${ARDUPILOT_HOME}/modules/waf' ]]"
check "submodule: mavlink"     "[[ -d '${ARDUPILOT_HOME}/modules/mavlink' ]]"
check "MatekH743 board def"    "find '${ARDUPILOT_HOME}' -name 'MatekH743.py' -o -name 'MatekH743.json' 2>/dev/null | grep -q ."

# ── Cross-compile smoke test ─────────────────────────────────────────────────
echo ""; echo "Cross-compile:"
TMPDIR=$(mktemp -d)
cat > "${TMPDIR}/test.c" << 'EOF'
#include <stdint.h>
uint32_t x = 42;
int main(void) { return (int)x; }
EOF
check "Cortex-M7 compile" \
    "arm-none-eabi-gcc -mcpu=cortex-m7 -mthumb -mfloat-abi=hard -mfpu=fpv5-d16 -o ${TMPDIR}/t.elf ${TMPDIR}/test.c -nostartfiles"
check "Cortex-M7 ELF valid" \
    "arm-none-eabi-objdump -f ${TMPDIR}/t.elf | grep -q 'ARM'"
rm -rf "${TMPDIR}"

# ── Common fixes ─────────────────────────────────────────────────────────────
echo ""
if [[ "${FAIL}" -gt 0 ]]; then
    echo -e "${YELLOW}━━  ${FAIL} check(s) failed.  Suggested fixes:  ━━━━━━━━━━━━━━━${NC}"
    echo ""

    python3 -c "import em; v=tuple(int(x) for x in em.__version__.split('.')[:2]); assert v<(4,0)" 2>/dev/null || {
        echo "  FIX empy version:"
        echo "    pip3 install 'empy>=3.3.4,<4.0' --force-reinstall"
        echo ""
    }

    command -v arm-none-eabi-gcc &>/dev/null || {
        echo "  FIX arm-none-eabi toolchain not in PATH:"
        echo "    source ${SCRIPT_DIR}/07_setup_env.sh"
        echo "  or re-run step 3:"
        echo "    bash ${SCRIPT_DIR}/03_build_gcc_newlib.sh"
        echo ""
    }

    [[ -d "${ARDUPILOT_HOME}/modules/waf" ]] || {
        echo "  FIX missing waf submodule:"
        echo "    git -C ${ARDUPILOT_HOME} submodule update --init modules/waf"
        echo ""
    }

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${GREEN}All ${PASS} checks passed.  Your environment looks healthy.${NC}"
fi
echo ""

# ── Version summary ──────────────────────────────────────────────────────────
echo "Version summary:"
arm-none-eabi-gcc --version 2>/dev/null | head -1 || true
python3 --version 2>/dev/null || true
python3 -c "import em; print(f'  empy {em.__version__}')" 2>/dev/null || true
cmake --version 2>/dev/null | head -1 || true
ninja --version 2>/dev/null && echo "  ninja $( ninja --version)" || true
ccache --version 2>/dev/null | head -1 || true
