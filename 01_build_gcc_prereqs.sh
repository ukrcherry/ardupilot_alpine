#!/usr/bin/env bash
# =============================================================================
# 01_build_gcc_prereqs.sh
# Build GCC prerequisites from source:  GMP → MPFR → MPC → ISL
#
# These are also symlinked INTO the GCC source tree (the recommended method)
# so that GCC's own build system can use them without requiring them to be
# already installed.  We also install them to ${AP_PREFIX} so that cmake,
# ccache, etc. can find them when linking.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "01  GCC Prerequisites — GMP / MPFR / MPC / ISL"

require_cmd gcc
require_cmd make
require_cmd wget

# ---- Download URLs ----------------------------------------------------------
GMP_URL="https://gmplib.org/download/gmp/gmp-${VER_GMP}.tar.xz"
MPFR_URL="https://www.mpfr.org/mpfr-${VER_MPFR}/mpfr-${VER_MPFR}.tar.xz"
MPC_URL="https://ftp.gnu.org/gnu/mpc/mpc-${VER_MPC}.tar.gz"
ISL_URL="https://libisl.sourceforge.io/isl-${VER_ISL}.tar.xz"

build_autoconf_pkg() {
    local name="$1"
    local tarball="$2"
    local dir_name="$3"
    local extra_cfg="${4:-}"

    local stamp="${AP_SRC}/${dir_name}/_build/.install_done"
    if [[ -f "${stamp}" ]]; then
        log_info "${name} already built — skipping."
        return 0
    fi

    log_info "Building ${name} ..."

    # extract_to prints ONLY the directory path on stdout (log lines go to stderr)
    local src_dir
    src_dir=$(extract_to "${tarball}" "${dir_name}")

    # Guard: ensure we got a real path back, not log garbage
    if [[ ! -d "${src_dir}" ]]; then
        log_error "extract_to did not return a valid directory (got: '${src_dir}')"
    fi

    local build_dir="${src_dir}/_build"
    mkdir -p "${build_dir}"
    cd "${build_dir}"

    log_info "Configuring ${name} in ${build_dir} ..."
    # shellcheck disable=SC2086
    ../configure \
        --prefix="${AP_PREFIX}" \
        --enable-shared \
        --enable-static \
        --disable-nls \
        ${extra_cfg} \
        2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Compiling ${name} (jobs=${MAKE_JOBS}) ..."
    make -j"${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Installing ${name} ..."
    make install 2>&1 | tee -a "${AP_LOG}" >&2

    touch "${stamp}"
    log_ok "${name} installed to ${AP_PREFIX}"
}

# ---- GMP --------------------------------------------------------------------
TARBALL=$(fetch "${GMP_URL}")
build_autoconf_pkg "GMP ${VER_GMP}" "${TARBALL}" "gmp-${VER_GMP}"

# ---- MPFR  (needs GMP) ------------------------------------------------------
export LDFLAGS="-L${AP_PREFIX}/lib"
export CPPFLAGS="-I${AP_PREFIX}/include"
TARBALL=$(fetch "${MPFR_URL}")
build_autoconf_pkg "MPFR ${VER_MPFR}" "${TARBALL}" "mpfr-${VER_MPFR}" \
    "--with-gmp=${AP_PREFIX}"

# ---- MPC  (needs GMP + MPFR) ------------------------------------------------
TARBALL=$(fetch "${MPC_URL}")
build_autoconf_pkg "MPC ${VER_MPC}" "${TARBALL}" "mpc-${VER_MPC}" \
    "--with-gmp=${AP_PREFIX} --with-mpfr=${AP_PREFIX}"

# ---- ISL  (optional but enables Graphite loop optimisations in GCC) ---------
TARBALL=$(fetch "${ISL_URL}")
build_autoconf_pkg "ISL ${VER_ISL}" "${TARBALL}" "isl-${VER_ISL}" \
    "--with-gmp-prefix=${AP_PREFIX}"

# ---- Refresh linker cache ---------------------------------------------------
export PKG_CONFIG_PATH="${AP_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
log_ok "All GCC prerequisites built.  Proceed with 02_build_binutils.sh"
