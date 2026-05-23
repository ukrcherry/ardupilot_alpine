#!/usr/bin/env bash
# =============================================================================
# 02_build_binutils.sh
# Build GNU Binutils cross-assembler/linker for arm-none-eabi.
#
# Produces: arm-none-eabi-as, arm-none-eabi-ld, arm-none-eabi-ar,
#           arm-none-eabi-objcopy, arm-none-eabi-objdump …
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "02  Binutils ${VER_BINUTILS} → ${TARGET}"

require_cmd gcc
require_cmd make
require_cmd wget

BINUTILS_URL="https://ftp.gnu.org/gnu/binutils/binutils-${VER_BINUTILS}.tar.xz"
STAMP="${AP_SRC}/binutils-${VER_BINUTILS}/_build/.install_done"

if [[ -f "${STAMP}" ]]; then
    log_info "binutils-${VER_BINUTILS} already built — skipping."
else
    TARBALL=$(fetch "${BINUTILS_URL}")
    SRC_DIR=$(extract_to "${TARBALL}" "binutils-${VER_BINUTILS}")
    BUILD_DIR="${SRC_DIR}/_build"
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    log_info "Configuring binutils …"
    ../configure \
        --prefix="${AP_PREFIX}" \
        --target="${TARGET}" \
        --with-sysroot \
        --disable-nls \
        --disable-werror \
        --enable-lto \
        --enable-plugins \
        --enable-gold \
        --with-gmp="${AP_PREFIX}" \
        --with-mpfr="${AP_PREFIX}" \
        --with-mpc="${AP_PREFIX}" \
        --with-isl="${AP_PREFIX}" \
        2>&1 | tee -a "${AP_LOG}"

    log_info "Building binutils (jobs=${MAKE_JOBS}) …"
    make -j"${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}"

    log_info "Installing binutils …"
    make install 2>&1 | tee -a "${AP_LOG}"

    touch "${STAMP}"
    log_ok "binutils-${VER_BINUTILS} installed."
fi

# ---- Quick sanity check -----------------------------------------------------
for tool in ar as ld nm objcopy objdump ranlib strip; do
    bin="${TOOLCHAIN_BIN}/${TARGET}-${tool}"
    if [[ -x "${bin}" ]]; then
        log_ok "  ${TARGET}-${tool} found"
    else
        log_warn "  ${TARGET}-${tool} NOT found at ${bin}"
    fi
done

log_ok "Binutils complete.  Proceed with 03_build_gcc_newlib.sh"
