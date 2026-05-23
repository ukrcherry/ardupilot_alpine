#!/usr/bin/env bash
# =============================================================================
# 08_build_ardupilot.sh
# Run all four target waf commands:
#
#   1.  cd ardupilot && ./waf configure           (SITL / native)
#   2.  ./waf all                                  (build all vehicles for SITL)
#   3.  ./waf configure --board MatekH743          (STM32H743 embedded target)
#   4.  ./waf copter                               (ArduCopter for MatekH743)
#
# The script stops on any failure and prints a diagnostic.
# Re-running is safe — waf's incremental build skips unchanged files.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/07_setup_env.sh"

section "08  Build ArduPilot"

require_cmd python3
require_cmd "${TARGET}-gcc"

[[ -d "${ARDUPILOT_HOME}" ]] || \
    log_error "ArduPilot not found at ${ARDUPILOT_HOME}. Run 06_clone_ardupilot.sh first."

cd "${ARDUPILOT_HOME}"

WAF="python3 ./waf"

# ---- Helper: run waf and tee output; on failure dump last 40 lines ----------
run_waf() {
    local desc="$1"; shift
    local logfile="${AP_PREFIX}/waf_${desc// /_}.log"
    log_info "Running: ./waf $* …"
    if ${WAF} "$@" 2>&1 | tee "${logfile}" | tee -a "${AP_LOG}"; then
        log_ok "  waf $* — SUCCESS"
    else
        log_error "  waf $* — FAILED.  Last 40 lines of ${logfile}:"
        tail -40 "${logfile}" >&2
        exit 1
    fi
}

# ============================================================
# 1 & 2  SITL — native Linux build
# ============================================================
section "SITL build  (./waf configure + ./waf all)"

log_info "Configuring for SITL (native) …"
run_waf "sitl_configure" configure \
    --board sitl \
    --out build/sitl

log_info "Building all SITL vehicles (this takes a while) …"
run_waf "sitl_all" --board sitl all

SITL_COPTER="${ARDUPILOT_HOME}/build/sitl/bin/arducopter"
SITL_PLANE="${ARDUPILOT_HOME}/build/sitl/bin/arduplane"
if [[ -x "${SITL_COPTER}" ]]; then
    log_ok "SITL ArduCopter: ${SITL_COPTER}"
else
    log_warn "SITL ArduCopter binary not found at expected path."
fi

# ============================================================
# 3 & 4  MatekH743 embedded target
# ============================================================
section "MatekH743 embedded build  (./waf configure --board MatekH743 + ./waf copter)"

log_info "Verifying arm-none-eabi-gcc …"
${TARGET}-gcc --version | head -1 | tee -a "${AP_LOG}"

log_info "Configuring for MatekH743 …"
run_waf "matek_configure" configure \
    --board MatekH743 \
    --out build/MatekH743

log_info "Building ArduCopter for MatekH743 …"
run_waf "matek_copter" --board MatekH743 copter

MATEK_COPTER="${ARDUPILOT_HOME}/build/MatekH743/bin/arducopter.bin"
MATEK_COPTER_ELF="${ARDUPILOT_HOME}/build/MatekH743/bin/arducopter"

if [[ -f "${MATEK_COPTER}" ]]; then
    SIZE=$(du -h "${MATEK_COPTER}" | cut -f1)
    log_ok "MatekH743 firmware: ${MATEK_COPTER}  (${SIZE})"
    log_ok "ELF:                ${MATEK_COPTER_ELF}"
else
    log_warn "Expected firmware not found at ${MATEK_COPTER}"
    find "${ARDUPILOT_HOME}/build/MatekH743" -name "*.bin" 2>/dev/null | head -5 | tee -a "${AP_LOG}"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ALL BUILDS SUCCESSFUL${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  SITL binaries:     ${ARDUPILOT_HOME}/build/sitl/bin/"
echo "  MatekH743 firmware:${ARDUPILOT_HOME}/build/MatekH743/bin/"
echo ""
echo "  To flash MatekH743:"
echo "    arm-none-eabi-gdb -ex \"target extended-remote :3333\" \\"
echo "      -ex \"load\" ${MATEK_COPTER_ELF}"
echo "  or upload arducopter.bin via Mission Planner / QGroundControl."
echo ""
