#!/usr/bin/env bash
# =============================================================================
# 04_build_host_tools.sh
# Install host build tools: cmake, ninja, ccache.
#
# WHY ALPINE PACKAGES INSTEAD OF FROM-SOURCE:
#   cmake 3.27+ bundles cmcppdap (DAP debugger library) which requires C++17
#   features that fail to compile under Alpine/musl's strict environment.
#   ninja and ccache have similar dependency issues.  Alpine's own packages
#   are correctly compiled for musl and are the same or newer versions than
#   what we were building from source.  The arm-none-eabi GCC toolchain
#   (scripts 02/03) is still fully compiled from source — that's the part
#   that matters for producing correct embedded firmware.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "04  Host tools — cmake / ninja / ccache  (Alpine packages)"

if ! command -v apk &>/dev/null; then
    log_error "apk not found — this script requires Alpine Linux."
fi

# ---- Install packages -------------------------------------------------------
TOOL_PKGS=(
    cmake
    ninja
    ccache
    make          # GNU make (should already be present from build-base)
    py3-pip       # ensure pip is present for step 05
)

log_info "Installing host tools via apk ..."
if [[ "$EUID" -ne 0 ]]; then
    sudo apk add --no-cache "${TOOL_PKGS[@]}" 2>&1 | tee -a "${AP_LOG}" >&2
else
    apk add --no-cache "${TOOL_PKGS[@]}" 2>&1 | tee -a "${AP_LOG}" >&2
fi

# ---- Verify -----------------------------------------------------------------
log_info "Verifying installed tools ..."
ALL_OK=1
for tool in cmake ninja ccache; do
    if command -v "${tool}" &>/dev/null; then
        ver=$("${tool}" --version 2>&1 | head -1)
        log_ok "  ${tool}: ${ver}"
    else
        log_warn "  ${tool}: NOT FOUND"
        ALL_OK=0
    fi
done
[[ "${ALL_OK}" -eq 1 ]] || log_error "One or more tools missing after apk install."

# ---- ccache symlinks for the ARM cross-compiler ----------------------------
# ArduPilot's waf looks for arm-none-eabi-gcc etc. via ccache.
# We place symlinks in ${AP_PREFIX}/lib/ccache so they can be prepended to
# PATH and transparently wrap the real cross-compiler binaries.
log_info "Setting up ccache symlinks for ${TARGET} ..."
CCACHE_DIR="${AP_PREFIX}/lib/ccache"
mkdir -p "${CCACHE_DIR}"
CCACHE_BIN=$(command -v ccache)

for tool in gcc g++ gcc-ar gcov gcc-nm gcc-ranlib; do
    LINK="${CCACHE_DIR}/${TARGET}-${tool}"
    if [[ ! -L "${LINK}" ]]; then
        ln -sf "${CCACHE_BIN}" "${LINK}"
        log_info "  created: ${LINK}"
    else
        log_info "  exists:  ${LINK}"
    fi
done
# Also wrap native gcc/g++ for SITL builds
for tool in gcc g++; do
    LINK="${CCACHE_DIR}/${tool}"
    [[ -L "${LINK}" ]] || ln -sf "${CCACHE_BIN}" "${LINK}"
done

log_info ""
log_info "To activate ccache, ensure this is at the FRONT of PATH:"
log_info "  export PATH=\"${CCACHE_DIR}:\${PATH}\""
log_info "(07_setup_env.sh does this automatically)"

log_ok "Host tools ready.  Proceed with 05_python_packages.sh"
