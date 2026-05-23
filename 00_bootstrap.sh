#!/usr/bin/env bash
# =============================================================================
# 00_bootstrap.sh
# Install the minimal set of Alpine BINARY packages needed as a HOST toolchain
# so we can compile all subsequent dependencies from source.
#
# WHY binary packages here?
#   Alpine's musl-based system is itself needed to host gcc at build time.
#   Everything installed here is ONLY the scaffolding compiler; every ArduPilot
#   dependency (arm-none-eabi GCC, cmake, ninja, ccache …) is built from source
#   in the later scripts.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "00  Bootstrap — Alpine host packages"

# ---- Must run as root (or via sudo) ----------------------------------------
if [[ "$EUID" -ne 0 ]]; then
    log_error "This script must be run as root (or with sudo)."
fi

# ---- Enable community repo (needed for some dev packages) ------------------
REPOS_FILE=/etc/apk/repositories
if ! grep -q "^[^#]*community" "${REPOS_FILE}"; then
    log_info "Enabling community repository …"
    # Uncomment or append the community repo based on current mirror
    MIRROR=$(head -1 "${REPOS_FILE}" | sed 's|/[^/]*$||')
    echo "${MIRROR}/community" >> "${REPOS_FILE}"
fi

apk update

# ---- Core build scaffold ----------------------------------------------------
# build-base  : gcc g++ musl-dev make binutils libc-dev (host only)
# The host gcc here is ONLY used to compile our from-source tools.
HOST_PKGS=(
    build-base          # gcc g++ musl-dev make binutils (host)
    musl-dev            # C standard library headers
    linux-headers       # Kernel headers (needed by GCC build system checks)

    # Source control
    git

    # Archive / download tools
    wget
    curl
    tar
    bzip2               # 'tar' on Alpine busybox may not decompress bz2 inline
    xz                  # for .tar.xz archives
    unzip
    gzip

    # Build system helpers
    bash
    coreutils           # provides realpath, nproc, etc. (busybox versions differ)
    util-linux          # for getopt etc.
    file                # 'file' command used in configure scripts
    patch

    # GCC build-time prerequisites (host tools, not our from-source ones)
    gawk                # GNU awk; used by GCC build scripts
    flex
    bison
    texinfo             # makeinfo — needed by GCC/binutils docs; use --disable-docs if missing
    m4
    automake
    autoconf
    libtool
    pkgconf             # pkg-config

    # GCC prerequisite LIBRARY headers (GMP/MPFR/MPC will be compiled from
    # source, but we need their development headers available to link the
    # bootstrap compiler itself during GCC's own build pass)
    gmp-dev
    mpfr-dev
    mpc1-dev

    # SSL for wget/curl (firmware.ardupilot.org needs HTTPS)
    openssl-dev
    ca-certificates

    # Python 3 — waf is a Python script; Alpine's python3 is sufficient
    python3
    py3-pip
    python3-dev         # headers needed when pip builds C-extension wheels

    # zlib (used by many build systems including GCC itself for LTO)
    zlib-dev

    # expat (used by Python and other tools)
    expat-dev

    # libffi (needed by Python ctypes, pip etc.)
    libffi-dev

    # ncurses (GCC's build system feature checks)
    ncurses-dev

    # rsync (useful for mirroring / incremental operations)
    rsync
)

log_info "Installing host packages …"
apk add --no-cache "${HOST_PKGS[@]}" 2>&1 | tee -a "${AP_LOG}"
log_ok "Host packages installed."

# ---- Create prefix directory tree ------------------------------------------
install -d "${AP_PREFIX}" "${AP_SRC}"
touch "${AP_LOG}"
chmod 666 "${AP_LOG}"
log_ok "Directory tree created under ${AP_PREFIX}"

# ---- Verify required commands -----------------------------------------------
for cmd in gcc g++ make wget git python3 pip3 gawk flex bison patch; do
    command -v "${cmd}" &>/dev/null && log_ok "  found: ${cmd}" || log_warn "  NOT found: ${cmd}"
done

# ---- Python baseline (pip itself) -------------------------------------------
log_info "Upgrading pip …"
pip3 install --upgrade pip setuptools wheel 2>&1 | tee -a "${AP_LOG}"

log_ok "Bootstrap complete.  Proceed with 01_build_gcc_prereqs.sh"
