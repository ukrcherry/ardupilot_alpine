#!/usr/bin/env bash
# =============================================================================
# 06_clone_ardupilot.sh
# Clone the ArduPilot repository and recursively initialise all submodules.
#
# The submodule tree is large (~1 GB network): waf, mavlink definitions,
# libraries, SITL models, etc.  This script is resumable — interrupted clones
# can be continued by re-running.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "06  Clone ArduPilot → ${ARDUPILOT_HOME}"

require_cmd git

# Allow override via environment: ARDUPILOT_REPO=https://... ./06_clone_ardupilot.sh
ARDUPILOT_REPO="${ARDUPILOT_REPO:-https://github.com/ArduPilot/ardupilot.git}"
# Set ARDUPILOT_BRANCH to checkout a specific tag/branch, e.g. "ArduCopter-4.5.0"
ARDUPILOT_BRANCH="${ARDUPILOT_BRANCH:-}"

# ---- Clone (skip if already present) ----------------------------------------
if [[ -d "${ARDUPILOT_HOME}/.git" ]]; then
    log_info "ArduPilot repo already present at ${ARDUPILOT_HOME}"
    log_info "Fetching latest changes …"
    git -C "${ARDUPILOT_HOME}" fetch --all --tags 2>&1 | tee -a "${AP_LOG}"
else
    log_info "Cloning ArduPilot from ${ARDUPILOT_REPO} …"
    git clone "${ARDUPILOT_REPO}" "${ARDUPILOT_HOME}" 2>&1 | tee -a "${AP_LOG}"
fi

# ---- Optional: checkout a specific branch/tag --------------------------------
if [[ -n "${ARDUPILOT_BRANCH}" ]]; then
    log_info "Checking out ${ARDUPILOT_BRANCH} …"
    git -C "${ARDUPILOT_HOME}" checkout "${ARDUPILOT_BRANCH}" 2>&1 | tee -a "${AP_LOG}"
fi

log_info "Current HEAD:"
git -C "${ARDUPILOT_HOME}" log --oneline -1 | tee -a "${AP_LOG}"

# ---- Submodule initialisation -----------------------------------------------
log_info "Initialising submodules (this may take several minutes) …"
git -C "${ARDUPILOT_HOME}" submodule update --init --recursive --jobs="${MAKE_JOBS}" \
    2>&1 | tee -a "${AP_LOG}"

# ---- Verify key submodules --------------------------------------------------
log_info "Verifying key submodules …"
for sub in \
    modules/waf \
    modules/mavlink \
    libraries/AP_Common \
    ArduCopter
do
    if [[ -d "${ARDUPILOT_HOME}/${sub}" ]]; then
        log_ok "  ${sub}"
    else
        log_warn "  MISSING: ${sub}"
    fi
done

log_ok "ArduPilot cloned and submodules initialised."
log_ok "Location: ${ARDUPILOT_HOME}"
log_ok "Proceed with 07_setup_env.sh or 08_build_ardupilot.sh"
