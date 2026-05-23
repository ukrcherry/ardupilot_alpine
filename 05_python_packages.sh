#!/usr/bin/env bash
# =============================================================================
# 05_python_packages.sh
# Install all Python packages required by ArduPilot's waf build system
# and SITL.  Packages are installed from PyPI source distributions (sdist)
# where possible so the C extensions are compiled from source.
#
# Key packages:
#   empy < 4.0   — waf template engine (ArduPilot is NOT compatible with empy 4+)
#   future       — Python 2/3 compatibility shims used in waf scripts
#   lxml         — XML processing
#   pymavlink    — MAVLink protocol library (compiled C extension)
#   pexpect      — For SITL test automation
#   pyserial     — Serial port access
#   MAVProxy     — Ground control station (optional, for SITL)
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "05  Python packages"

require_cmd python3
require_cmd pip3

PYTHON=$(command -v python3)
PIP="${PYTHON} -m pip"

log_info "Python: $("${PYTHON}" --version)"
log_info "pip:    $(${PIP} --version)"

# ---- Upgrade pip itself first -----------------------------------------------
${PIP} install --upgrade pip setuptools wheel 2>&1 | tee -a "${AP_LOG}"

# ---- Function: install a package, skip if already satisfying version --------
pip_install() {
    local spec="$1"
    log_info "pip install ${spec} …"
    ${PIP} install --no-binary :all: "${spec}" 2>&1 | tee -a "${AP_LOG}" || {
        # Some packages have no sdist (only wheel) — fall back to any format
        log_warn "  Source install failed; falling back to wheel …"
        ${PIP} install "${spec}" 2>&1 | tee -a "${AP_LOG}"
    }
}

# ============================================================
# Core waf dependencies  (MUST be installed for ./waf configure to run)
# ============================================================

# empy — CRITICAL: ArduPilot requires empy < 4.0
# empy 4.x broke backward compatibility and will cause waf to fail with
# "AttributeError: module 'em' has no attribute 'BUFFERED_OPT'"
pip_install "empy>=3.3.4,<4.0"

# future — Python 2/3 shims used extensively in waf scripts
pip_install "future"

# pyserial
pip_install "pyserial"

# pexpect — used by autotest
pip_install "pexpect"

# lxml — XML/HTML processing
${PIP} install "lxml" 2>&1 | tee -a "${AP_LOG}"

# ============================================================
# MAVLink / MAVProxy
# ============================================================

# pymavlink — compiled extension; needs libxml2 + libxslt headers
${PIP} install "pymavlink" 2>&1 | tee -a "${AP_LOG}"

# MAVProxy GCS (optional but required for SITL interactive use)
${PIP} install "MAVProxy" 2>&1 | tee -a "${AP_LOG}" || \
    log_warn "MAVProxy install failed (optional — SITL headless builds still work)."

# ============================================================
# Additional SITL / dev tools
# ============================================================
pip_install "dronecan"      # DroneCAN protocol
pip_install "intelhex"      # Intel HEX file handling (firmware upload)
pip_install "construct"     # binary data structures
pip_install "matplotlib"    # SITL graphs (optional)
pip_install "scipy"         # math (optional)
pip_install "numpy"         # arrays (optional, used by MAVProxy)

# ============================================================
# Verify critical packages
# ============================================================
log_info "Verifying critical packages …"
FAILED=0
for pkg_check in \
    "import em; assert hasattr(em,'expand'), 'empy version incompatible'" \
    "import future" \
    "import serial" \
    "import pexpect" \
    "import pymavlink"
do
    if "${PYTHON}" -c "${pkg_check}" 2>/dev/null; then
        log_ok "  OK: ${pkg_check%%';'*}"
    else
        log_warn "  FAIL: ${pkg_check%%';'*}"
        FAILED=$((FAILED+1))
    fi
done

# Check empy version is < 4.0
EMPY_VER=$("${PYTHON}" -c "import em; print(em.__version__)" 2>/dev/null || echo "unknown")
log_info "empy version: ${EMPY_VER}"
if "${PYTHON}" -c "import em; v=tuple(int(x) for x in em.__version__.split('.')[:2]); assert v < (4,0), 'empy >= 4.0 will break waf!'" 2>/dev/null; then
    log_ok "  empy version check PASSED (${EMPY_VER} < 4.0)"
else
    log_warn "  empy version check FAILED — empy ${EMPY_VER} >= 4.0 will break ./waf"
    log_warn "  Run: pip install 'empy>=3.3.4,<4.0'"
fi

[[ "${FAILED}" -eq 0 ]] && log_ok "All critical Python packages verified." \
    || log_warn "${FAILED} package(s) need attention."

log_ok "Python packages done.  Proceed with 06_clone_ardupilot.sh"
