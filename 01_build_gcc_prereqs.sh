#!/usr/bin/env bash
# =============================================================================
# 01_build_gcc_prereqs.sh
# Build GCC prerequisites from source:  GMP → MPFR → MPC → ISL
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "01  GCC Prerequisites — GMP / MPFR / MPC / ISL"

# ============================================================
# Pre-flight: verify the host C compiler actually works.
# require_cmd only checks the binary exists; here we compile
# a real file.  If it fails we auto-run 00_bootstrap.sh.
# ============================================================
preflight_compiler() {
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "${tmpdir}/test.c" << 'EOF'
#include <stdio.h>
int main(void) { return 0; }
EOF
    if gcc -o "${tmpdir}/test" "${tmpdir}/test.c" 2>/dev/null; then
        log_ok "Host compiler smoke-test passed."
        rm -rf "${tmpdir}"
        return 0
    else
        rm -rf "${tmpdir}"
        return 1
    fi
}

if ! preflight_compiler; then
    log_warn "Host compiler is not working (missing musl-dev / build-base)."
    log_warn "Running 00_bootstrap.sh to install required packages ..."
    if [[ "$EUID" -ne 0 ]]; then
        sudo bash "${SCRIPT_DIR}/00_bootstrap.sh"
    else
        bash "${SCRIPT_DIR}/00_bootstrap.sh"
    fi
    # Re-test
    preflight_compiler || log_error "Host compiler still broken after bootstrap. Check 00_bootstrap.sh output."
fi

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
    # extra_cfg is passed as individual args from $4 onward (avoids quoting issues
    # when the string contains spaces — the old single-string approach split wrong)
    shift 3
    local extra_cfg_args=("$@")

    local stamp="${AP_SRC}/${dir_name}/_build/.install_done"
    if [[ -f "${stamp}" ]]; then
        log_info "${name} already built — skipping."
        return 0
    fi

    log_info "Building ${name} ..."

    # extract_to prints ONLY the directory path on stdout
    local src_dir
    src_dir=$(extract_to "${tarball}" "${dir_name}")

    if [[ ! -d "${src_dir}" ]]; then
        log_error "extract_to did not return a valid directory (got: '${src_dir}')"
    fi

    local build_dir="${src_dir}/_build"
    mkdir -p "${build_dir}"
    cd "${build_dir}"

    log_info "Configuring ${name} ..."
    ../configure \
        --prefix="${AP_PREFIX}" \
        --enable-shared \
        --enable-static \
        "${extra_cfg_args[@]}" \
        2>&1 | tee -a "${AP_LOG}" >&2
    # Note: --disable-nls is NOT passed to GMP/MPFR/MPC/ISL — they don't
    # support it and GMP's configure will error on unrecognised options.

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
#  ↑ no extra flags; GMP's configure is strict about unknown options

# ---- MPFR  (needs GMP) ------------------------------------------------------
export LDFLAGS="-L${AP_PREFIX}/lib"
export CPPFLAGS="-I${AP_PREFIX}/include"
TARBALL=$(fetch "${MPFR_URL}")
build_autoconf_pkg "MPFR ${VER_MPFR}" "${TARBALL}" "mpfr-${VER_MPFR}" \
    "--with-gmp=${AP_PREFIX}"

# ---- MPC  (needs GMP + MPFR) ------------------------------------------------
TARBALL=$(fetch "${MPC_URL}")
build_autoconf_pkg "MPC ${VER_MPC}" "${TARBALL}" "mpc-${VER_MPC}" \
    "--with-gmp=${AP_PREFIX}" "--with-mpfr=${AP_PREFIX}"

# ---- ISL  (optional but enables Graphite loop optimisations in GCC) ---------
TARBALL=$(fetch "${ISL_URL}")
build_autoconf_pkg "ISL ${VER_ISL}" "${TARBALL}" "isl-${VER_ISL}" \
    "--with-gmp-prefix=${AP_PREFIX}"

# ---- Refresh pkg-config path ------------------------------------------------
export PKG_CONFIG_PATH="${AP_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
log_ok "All GCC prerequisites built.  Proceed with 02_build_binutils.sh"
