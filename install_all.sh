#!/usr/bin/env bash
# =============================================================================
# install_all.sh — Master orchestrator
# Runs every step in order from a fresh Alpine Linux installation.
#
# Usage:
#   sudo ./install_all.sh            # full run (steps 0-8)
#   sudo ./install_all.sh --from 3   # resume from step 3
#   sudo ./install_all.sh --only 5   # run only step 5
#   sudo ./install_all.sh --skip-sitl # skip the slow ./waf all SITL build
#
# Steps:
#   0  Bootstrap: minimal apk packages
#   1  Build GCC prerequisites (GMP, MPFR, MPC, ISL) from source
#   2  Build binutils for arm-none-eabi from source
#   3  Build GCC + Newlib for arm-none-eabi from source
#   4  Build cmake, ninja, ccache from source
#   5  Install Python packages (empy<4, future, pymavlink …)
#   6  Clone ArduPilot + submodules
#   7  (env setup — sourced automatically by step 8)
#   8  Build ArduPilot (waf configure, waf all, MatekH743, copter)
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- CLI parsing ------------------------------------------------------------
FROM_STEP=0
ONLY_STEP=""
SKIP_SITL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)  FROM_STEP="$2"; shift 2 ;;
        --only)  ONLY_STEP="$2"; shift 2 ;;
        --skip-sitl) SKIP_SITL=1; shift ;;
        -h|--help)
            sed -n '/^# Usage:/,/^# ===/p' "$0" | head -20
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

source "${SCRIPT_DIR}/config.env"

# ---- Timing -----------------------------------------------------------------
START_TIME=$(date +%s)
elapsed() { echo $(( ($(date +%s) - START_TIME) / 60 )) ; }

# ---- Step runner ------------------------------------------------------------
run_step() {
    local num="$1"
    local script="$2"
    local desc="$3"

    [[ -n "${ONLY_STEP}" && "${ONLY_STEP}" != "${num}" ]] && return 0
    [[ "${num}" -lt "${FROM_STEP}" ]] && return 0

    section "STEP ${num}: ${desc}"
    echo ""

    if [[ "${num}" -eq 0 ]]; then
        # Bootstrap requires root
        if [[ "$EUID" -ne 0 ]]; then
            log_warn "Step 0 requires root. Running with sudo …"
            sudo bash "${SCRIPT_DIR}/${script}"
        else
            bash "${SCRIPT_DIR}/${script}"
        fi
    else
        bash "${SCRIPT_DIR}/${script}"
    fi

    log_ok "Step ${num} done  ($(elapsed) min elapsed)"
}

# ---- Banner -----------------------------------------------------------------
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     ArduPilot build environment — Alpine Linux           ║${NC}"
echo -e "${CYAN}║     All dependencies compiled from source                ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Build prefix : ${AP_PREFIX}"
echo "  ArduPilot    : ${ARDUPILOT_HOME}"
echo "  Parallel jobs: ${MAKE_JOBS}"
echo "  Log          : ${AP_LOG}"
echo ""
echo "  Estimated time:"
echo "    Steps 1-3 (GCC from source):  60-120 min  depending on CPU"
echo "    Steps 4   (cmake/ninja/ccache): 10-20 min"
echo "    Step  8   (waf all SITL):       10-20 min"
echo "    Step  8   (waf copter MatekH743): 5-10 min"
echo ""

if [[ "${FROM_STEP}" -eq 0 && -z "${ONLY_STEP}" ]]; then
    read -rp "  Press Enter to begin or Ctrl-C to abort …" _
fi

mkdir -p "${AP_PREFIX}" "${AP_SRC}"
touch "${AP_LOG}"

# ---- Execute steps ----------------------------------------------------------
run_step 0 "00_bootstrap.sh"       "Alpine host packages (apk)"
run_step 1 "01_build_gcc_prereqs.sh" "GCC prerequisites from source"
run_step 2 "02_build_binutils.sh"  "binutils for arm-none-eabi"
run_step 3 "03_build_gcc_newlib.sh" "GCC ${VER_GCC} + Newlib (arm-none-eabi)"
run_step 4 "04_build_host_tools.sh" "cmake / ninja / ccache from source"
run_step 5 "05_python_packages.sh" "Python packages"
run_step 6 "06_clone_ardupilot.sh" "Clone ArduPilot + submodules"

# Step 8 honours --skip-sitl by passing an env variable
if [[ "${SKIP_SITL}" -eq 1 ]]; then
    export AP_SKIP_SITL=1
fi
run_step 8 "08_build_ardupilot.sh" "Build ArduPilot (SITL + MatekH743)"

# ---- Final summary ----------------------------------------------------------
TOTAL=$(elapsed)
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ALL DONE  — total time: ${TOTAL} minutes                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Add to your ~/.bashrc or ~/.profile:"
echo ""
echo "    source ${SCRIPT_DIR}/07_setup_env.sh"
echo ""
echo "  Then build at any time:"
echo "    cd ${ARDUPILOT_HOME}"
echo "    ./waf configure --board MatekH743 && ./waf copter"
echo ""
echo "  Full build log: ${AP_LOG}"
