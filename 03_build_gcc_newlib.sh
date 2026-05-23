#!/usr/bin/env bash
# =============================================================================
# 03_build_gcc_newlib.sh
# Build the arm-none-eabi GCC cross compiler together with Newlib.
#
# Build order:
#   Stage 1 — GCC C-only (--without-headers, no libc yet)
#   Newlib   — Compiled with stage-1 arm-none-eabi-gcc
#   Stage 2  — Full GCC C+C++ with Newlib as sysroot
#
# Prerequisites (GMP/MPFR/MPC/ISL) come from Alpine apk packages installed
# by 01_build_gcc_prereqs.sh  — there are NO source directories for them,
# so do NOT attempt to symlink them into the GCC tree.  We use --with-gmp=
# etc. pointing at /usr instead.
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
[[ -f "${AP_PREFIX}/prereqs.env" ]] && source "${AP_PREFIX}/prereqs.env"
PRE="${GCC_PREREQ_PREFIX:-/usr}"   # shorthand: /usr

section "03  GCC ${VER_GCC} + Newlib ${VER_NEWLIB} → ${TARGET}"

require_cmd "${TARGET}-as"
require_cmd make
require_cmd wget

# ---- URLs -------------------------------------------------------------------
GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-${VER_GCC}/gcc-${VER_GCC}.tar.xz"
# Newlib 4.4.0 is the latest stable; 4.3.0 was never released as a tarball.
NEWLIB_URL="https://sourceware.org/pub/newlib/newlib-${VER_NEWLIB}.tar.gz"

# Verify the Newlib URL exists before spending time on GCC
check_url() {
    local url="$1"
    local http_code
    http_code=$(wget --spider --server-response "${url}" 2>&1 \
                | grep "HTTP/" | tail -1 | awk '{print $2}')
    [[ "${http_code}" == "200" ]] || {
        log_error "URL returned HTTP ${http_code}: ${url}
  Newlib releases: https://sourceware.org/pub/newlib/
  Update VER_NEWLIB in config.env to a version that exists."
    }
}
log_info "Checking Newlib ${VER_NEWLIB} URL ..."
check_url "${NEWLIB_URL}"

# ---- Common GCC configure flags ---------------------------------------------
GCC_COMMON_FLAGS=(
    --prefix="${AP_PREFIX}"
    --target="${TARGET}"
    --with-sysroot="${AP_PREFIX}/${TARGET}"
    --with-native-system-header-dir=/include
    # Prerequisites come from Alpine apk packages at /usr
    --with-gmp="${PRE}"
    --with-mpfr="${PRE}"
    --with-mpc="${PRE}"
    --with-isl="${PRE}"
    --disable-nls
    --disable-shared
    --disable-threads
    --disable-tls
    --with-newlib
    --without-headers
    --enable-lto
    --enable-plugins
    --disable-libgomp
    --disable-libmudflap
    --disable-libquadmath
    --disable-libssp
    --disable-libstdcxx-pch
    --with-gnu-as
    --with-gnu-ld
    --with-multilib-list=rmprofile
    --enable-multilib
)

# ---- Download sources -------------------------------------------------------
log_info "Fetching GCC ${VER_GCC} ..."
GCC_TARBALL=$(fetch "${GCC_URL}")
GCC_SRC=$(extract_to "${GCC_TARBALL}" "gcc-${VER_GCC}")
[[ -d "${GCC_SRC}" ]] || log_error "GCC source not found: '${GCC_SRC}'"

log_info "Fetching Newlib ${VER_NEWLIB} ..."
NEWLIB_TARBALL=$(fetch "${NEWLIB_URL}")
NEWLIB_SRC=$(extract_to "${NEWLIB_TARBALL}" "newlib-${VER_NEWLIB}")
[[ -d "${NEWLIB_SRC}" ]] || log_error "Newlib source not found: '${NEWLIB_SRC}'"

# ---- Symlink Newlib into GCC source tree ------------------------------------
# GMP/MPFR/MPC/ISL are NOT symlinked — they come from /usr (apk packages).
# Newlib IS symlinked so GCC's build system can build it in one pass.
log_info "Symlinking newlib + libgloss into GCC source tree ..."
for subdir in newlib libgloss; do
    if [[ -d "${NEWLIB_SRC}/${subdir}" ]]; then
        ln -sfn "${NEWLIB_SRC}/${subdir}" "${GCC_SRC}/${subdir}"
        log_info "  symlinked: ${GCC_SRC}/${subdir} → ${NEWLIB_SRC}/${subdir}"
    else
        log_warn "  ${subdir} not found in ${NEWLIB_SRC} — skipping symlink"
    fi
done

# ============================================================
# Stage 1 — C-only compiler (needed to compile Newlib)
# ============================================================
STAGE1_STAMP="${GCC_SRC}/_build_stage1/.install_done"
if [[ -f "${STAGE1_STAMP}" ]]; then
    log_info "GCC stage-1 already built — skipping."
else
    log_info "Configuring GCC stage 1 (C only) ..."
    rm -rf "${GCC_SRC}/_build_stage1"
    mkdir -p "${GCC_SRC}/_build_stage1"
    cd "${GCC_SRC}/_build_stage1"

    ../configure \
        "${GCC_COMMON_FLAGS[@]}" \
        --enable-languages=c \
        2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Building GCC stage 1 (jobs=${MAKE_JOBS}) ..."
    make -j"${MAKE_JOBS}" all-gcc 2>&1 | tee -a "${AP_LOG}" >&2
    make install-gcc 2>&1 | tee -a "${AP_LOG}" >&2

    touch "${STAGE1_STAMP}"
    log_ok "GCC stage 1 done."
fi

# ============================================================
# Newlib — compiled with the stage-1 arm-none-eabi-gcc
# ============================================================
NEWLIB_STAMP="${GCC_SRC}/_build_newlib/.install_done"
if [[ -f "${NEWLIB_STAMP}" ]]; then
    log_info "Newlib already built — skipping."
else
    log_info "Configuring Newlib ${VER_NEWLIB} ..."
    rm -rf "${GCC_SRC}/_build_newlib"
    mkdir -p "${GCC_SRC}/_build_newlib"
    cd "${GCC_SRC}/_build_newlib"

    "${NEWLIB_SRC}/configure" \
        --prefix="${AP_PREFIX}" \
        --target="${TARGET}" \
        --enable-multilib \
        --enable-newlib-io-long-long \
        --enable-newlib-register-fini \
        --disable-newlib-supplied-syscalls \
        --disable-nls \
        2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Building Newlib (jobs=${MAKE_JOBS}) ..."
    make -j"${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}" >&2
    make install 2>&1 | tee -a "${AP_LOG}" >&2

    touch "${NEWLIB_STAMP}"
    log_ok "Newlib done."
fi

# ============================================================
# Stage 2 — Full GCC C + C++  (with Newlib as sysroot)
# ============================================================
STAGE2_STAMP="${GCC_SRC}/_build_stage2/.install_done"
if [[ -f "${STAGE2_STAMP}" ]]; then
    log_info "GCC stage-2 already built — skipping."
else
    log_info "Configuring GCC stage 2 (C + C++) ..."
    rm -rf "${GCC_SRC}/_build_stage2"
    mkdir -p "${GCC_SRC}/_build_stage2"
    cd "${GCC_SRC}/_build_stage2"

    ../configure \
        "${GCC_COMMON_FLAGS[@]}" \
        --enable-languages=c,c++ \
        --with-headers="${AP_PREFIX}/${TARGET}/include" \
        2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Building GCC stage 2 (jobs=${MAKE_JOBS}) ..."
    make -j"${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}" >&2
    make install 2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Building libstdc++-v3 ..."
    make -j"${MAKE_JOBS}" all-target-libstdc++-v3 2>&1 | tee -a "${AP_LOG}" >&2
    make install-target-libstdc++-v3 2>&1 | tee -a "${AP_LOG}" >&2

    touch "${STAGE2_STAMP}"
    log_ok "GCC stage 2 done."
fi

# ============================================================
# Sanity checks
# ============================================================
log_info "Verifying arm-none-eabi toolchain ..."
for tool in gcc g++ ar nm objcopy objdump ranlib strip; do
    bin="${TOOLCHAIN_BIN}/${TARGET}-${tool}"
    if [[ -x "${bin}" ]]; then
        ver=$("${bin}" --version 2>&1 | head -1)
        log_ok "  ${TARGET}-${tool}  →  ${ver}"
    else
        log_warn "  ${TARGET}-${tool} NOT found at ${bin}"
    fi
done

TMPDIR=$(mktemp -d)
cat > "${TMPDIR}/hello.c" << 'EOF'
int main(void) { return 0; }
EOF
if "${TOOLCHAIN_BIN}/${TARGET}-gcc" \
       -mcpu=cortex-m7 -mthumb -mfloat-abi=hard -mfpu=fpv5-d16 \
       -o "${TMPDIR}/hello.elf" "${TMPDIR}/hello.c" -nostartfiles 2>&1 | \
       tee -a "${AP_LOG}" >&2 ; then
    log_ok "Cross-compilation smoke test PASSED (Cortex-M7)."
else
    log_warn "Cross-compilation smoke test FAILED — check build log."
fi
rm -rf "${TMPDIR}"

log_ok "GCC + Newlib complete.  Proceed with 04_build_host_tools.sh"
