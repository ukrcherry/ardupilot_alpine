#!/usr/bin/env bash
# =============================================================================
# 01_build_gcc_prereqs.sh
# Build GCC prerequisites from source:  GMP → MPFR → MPC → ISL
#
# Alpine/musl-specific notes:
#   GMP's configure tries multiple ABIs and CPU-specific assembly variants;
#   on musl the test compilations fail for non-obvious reasons (pedantic +
#   strict musl headers, libgcc helper symbols, PIE defaults).  We bypass all
#   of this with: ABI=64, --disable-assembly, and explicit CC/CFLAGS.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "01  GCC Prerequisites — GMP / MPFR / MPC / ISL"

# ============================================================
# Pre-flight: verify the host C compiler actually works.
# ============================================================
preflight_compiler() {
    local tmpdir
    tmpdir=$(mktemp -d)
    cat > "${tmpdir}/test.c" << 'EOF'
#include <stdio.h>
int main(void) { puts("ok"); return 0; }
EOF
    # Compile AND run — same as what GMP does
    if gcc -O2 -o "${tmpdir}/test" "${tmpdir}/test.c" 2>/dev/null \
       && "${tmpdir}/test" >/dev/null 2>&1; then
        log_ok "Host compiler smoke-test passed."
        rm -rf "${tmpdir}"
        return 0
    else
        rm -rf "${tmpdir}"
        return 1
    fi
}

if ! preflight_compiler; then
    log_warn "Host compiler not working — running 00_bootstrap.sh ..."
    if [[ "$EUID" -ne 0 ]]; then
        sudo bash "${SCRIPT_DIR}/00_bootstrap.sh"
    else
        bash "${SCRIPT_DIR}/00_bootstrap.sh"
    fi
    preflight_compiler || log_error "Compiler still broken after bootstrap."
fi

require_cmd make
require_cmd wget

# ---- Detect host triplet (for explicit --build/--host) ----------------------
HOST_TRIPLET=$(gcc -dumpmachine)
log_info "Host triplet: ${HOST_TRIPLET}"

# ---- Download URLs ----------------------------------------------------------
GMP_URL="https://gmplib.org/download/gmp/gmp-${VER_GMP}.tar.xz"
MPFR_URL="https://www.mpfr.org/mpfr-${VER_MPFR}/mpfr-${VER_MPFR}.tar.xz"
MPC_URL="https://ftp.gnu.org/gnu/mpc/mpc-${VER_MPC}.tar.gz"
ISL_URL="https://libisl.sourceforge.io/isl-${VER_ISL}.tar.xz"

# ---- Dump config.log on configure failure (huge debugging help) -------------
dump_config_log_on_fail() {
    local build_dir="$1"
    if [[ -f "${build_dir}/config.log" ]]; then
        log_warn "===== last 60 lines of config.log: ====="
        tail -60 "${build_dir}/config.log" >&2
        log_warn "===== full log: ${build_dir}/config.log ====="
    fi
}

build_autoconf_pkg() {
    local name="$1"
    local tarball="$2"
    local dir_name="$3"
    shift 3
    local extra_cfg_args=("$@")

    local stamp="${AP_SRC}/${dir_name}/_build/.install_done"
    if [[ -f "${stamp}" ]]; then
        log_info "${name} already built — skipping."
        return 0
    fi

    log_info "Building ${name} ..."

    local src_dir
    src_dir=$(extract_to "${tarball}" "${dir_name}")
    [[ -d "${src_dir}" ]] || log_error "extract_to returned invalid path: '${src_dir}'"

    local build_dir="${src_dir}/_build"
    # Wipe any half-finished previous attempt so configure starts clean
    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"
    cd "${build_dir}"

    log_info "Configuring ${name} ..."
    # Run configure; if it fails, dump config.log and exit
    if ! ../configure \
            --prefix="${AP_PREFIX}" \
            --build="${HOST_TRIPLET}" \
            --host="${HOST_TRIPLET}" \
            --enable-shared \
            --enable-static \
            "${extra_cfg_args[@]}" \
            2>&1 | tee -a "${AP_LOG}" >&2 ; then
        dump_config_log_on_fail "${build_dir}"
        log_error "configure failed for ${name}"
    fi
    # `set -o pipefail` means we also need to check PIPESTATUS for the actual
    # configure exit code (tee won't have failed)
    if [[ "${PIPESTATUS[0]:-0}" -ne 0 ]]; then
        dump_config_log_on_fail "${build_dir}"
        log_error "configure failed for ${name} (exit ${PIPESTATUS[0]})"
    fi

    log_info "Compiling ${name} (jobs=${MAKE_JOBS}) ..."
    make -j"${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}" >&2
    [[ "${PIPESTATUS[0]:-0}" -eq 0 ]] || log_error "make failed for ${name}"

    log_info "Installing ${name} ..."
    make install 2>&1 | tee -a "${AP_LOG}" >&2
    [[ "${PIPESTATUS[0]:-0}" -eq 0 ]] || log_error "make install failed for ${name}"

    touch "${stamp}"
    log_ok "${name} installed to ${AP_PREFIX}"
}

# ============================================================
# Compiler environment used by ALL prereqs.
# Crucially: NO -pedantic (GMP injects it by default and it breaks
# under musl's strict headers).  Just -O2 is enough.
# ============================================================
export CC=gcc
export CXX=g++
export CFLAGS="-O2"
export CXXFLAGS="-O2"

# ---- GMP --------------------------------------------------------------------
#
# Special-case for GMP:
#   ABI=64               — skip multi-ABI probing (avoids x32/i386 fallbacks)
#   --disable-assembly   — use C fallback instead of CPU-specific .S files,
#                          which are the source of "long long reliability"
#                          failures on musl.  Slightly slower but reliable.
#
TARBALL=$(fetch "${GMP_URL}")
GMP_STAMP="${AP_SRC}/gmp-${VER_GMP}/_build/.install_done"
if [[ -f "${GMP_STAMP}" ]]; then
    log_info "GMP ${VER_GMP} already built — skipping."
else
    log_info "Building GMP ${VER_GMP} ..."
    GMP_SRC=$(extract_to "${TARBALL}" "gmp-${VER_GMP}")
    [[ -d "${GMP_SRC}" ]] || log_error "GMP source not found: '${GMP_SRC}'"
    rm -rf "${GMP_SRC}/_build"
    mkdir -p "${GMP_SRC}/_build"
    cd "${GMP_SRC}/_build"

    log_info "Configuring GMP with ABI=64 --disable-assembly ..."
    if ! ABI=64 ../configure \
            --prefix="${AP_PREFIX}" \
            --build="${HOST_TRIPLET}" \
            --host="${HOST_TRIPLET}" \
            --enable-shared \
            --enable-static \
            --disable-assembly \
            2>&1 | tee -a "${AP_LOG}" >&2 ; then
        dump_config_log_on_fail "${GMP_SRC}/_build"
        log_error "GMP configure failed"
    fi
    [[ "${PIPESTATUS[0]:-0}" -eq 0 ]] || {
        dump_config_log_on_fail "${GMP_SRC}/_build"
        log_error "GMP configure failed (exit ${PIPESTATUS[0]})"
    }

    log_info "Compiling GMP (jobs=${MAKE_JOBS}) ..."
    make -j"${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}" >&2
    [[ "${PIPESTATUS[0]:-0}" -eq 0 ]] || log_error "GMP make failed"

    log_info "Installing GMP ..."
    make install 2>&1 | tee -a "${AP_LOG}" >&2
    [[ "${PIPESTATUS[0]:-0}" -eq 0 ]] || log_error "GMP install failed"

    touch "${GMP_STAMP}"
    log_ok "GMP ${VER_GMP} installed to ${AP_PREFIX}"
fi

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

# ---- Done -------------------------------------------------------------------
export PKG_CONFIG_PATH="${AP_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
log_ok "All GCC prerequisites built.  Proceed with 02_build_binutils.sh"
