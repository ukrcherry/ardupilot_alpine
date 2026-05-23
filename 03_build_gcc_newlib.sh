#!/usr/bin/env bash
# =============================================================================
# 03_build_gcc_newlib.sh
# Build the arm-none-eabi GCC cross compiler together with Newlib
# (the bare-metal C library for embedded targets).
#
# Build order required by a bare-metal toolchain:
#   Stage 1 — GCC C-only (no libc yet, uses --without-headers)
#   Newlib   — Compiled with stage-1 compiler
#   Stage 2  — Full GCC C+C++ with Newlib as the sysroot
#
# Resulting tools:
#   arm-none-eabi-gcc, arm-none-eabi-g++, arm-none-eabi-gdb (optional),
#   arm-none-eabi-gcc-ar, arm-none-eabi-lto-dump …
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
[[ -f "${AP_PREFIX}/prereqs.env" ]] && source "${AP_PREFIX}/prereqs.env"

section "03  GCC ${VER_GCC} + Newlib ${VER_NEWLIB} → ${TARGET}"

require_cmd "${TARGET}-as"      # binutils must already be installed
require_cmd make
require_cmd wget

GCC_URL="https://ftp.gnu.org/gnu/gcc/gcc-${VER_GCC}/gcc-${VER_GCC}.tar.xz"
NEWLIB_URL="https://sourceware.org/pub/newlib/newlib-${VER_NEWLIB}.tar.gz"

# Common GCC configure flags
# --with-newlib          : target uses newlib (no shared host libc)
# --with-headers         : path to newlib headers (set after downloading newlib)
# --disable-libstdcxx-*  : keep the C++ lib small for embedded
GCC_COMMON_FLAGS=(
    --prefix="${AP_PREFIX}"
    --target="${TARGET}"
    --with-sysroot="${AP_PREFIX}/${TARGET}"
    --with-native-system-header-dir=/include
    --with-gmp="${GCC_PREREQ_PREFIX:-/usr}"
    --with-mpfr="${GCC_PREREQ_PREFIX:-/usr}"
    --with-mpc="${GCC_PREREQ_PREFIX:-/usr}"
    --with-isl="${GCC_PREREQ_PREFIX:-/usr}"
    --disable-nls
    --disable-shared
    --disable-threads
    --disable-tls
    --with-newlib
    --without-headers
    --enable-languages=c,c++
    --enable-lto
    --enable-plugins
    --disable-libgomp
    --disable-libmudflap
    --disable-libquadmath
    --disable-libssp
    --disable-libstdcxx-pch
    --with-gnu-as
    --with-gnu-ld
    # Embedded ARM targets
    --with-multilib-list=rmprofile
    --enable-multilib
)

# ============================================================
# Download sources
# ============================================================
log_info "Fetching GCC ${VER_GCC} …"
GCC_TARBALL=$(fetch "${GCC_URL}")
GCC_SRC=$(extract_to "${GCC_TARBALL}" "gcc-${VER_GCC}")

log_info "Fetching Newlib ${VER_NEWLIB} …"
NEWLIB_TARBALL=$(fetch "${NEWLIB_URL}")
NEWLIB_SRC=$(extract_to "${NEWLIB_TARBALL}" "newlib-${VER_NEWLIB}")

# Symlink prerequisites INTO GCC source tree (GCC convention — simplifies build)
cd "${GCC_SRC}"
for lib in gmp mpfr mpc isl; do
    DIR=$(ls -d "${AP_SRC}/${lib}-"* 2>/dev/null | head -1)
    if [[ -n "${DIR}" && ! -L "${GCC_SRC}/${lib}" ]]; then
        ln -sfn "${DIR}" "${GCC_SRC}/${lib}"
        log_info "Symlinked ${lib} → ${DIR}"
    fi
done

# Symlink newlib directories into GCC source tree
# (allows a single configure/make to build both)
for subdir in newlib libgloss; do
    if [[ -d "${NEWLIB_SRC}/${subdir}" && ! -L "${GCC_SRC}/${subdir}" ]]; then
        ln -sfn "${NEWLIB_SRC}/${subdir}" "${GCC_SRC}/${subdir}"
        log_info "Symlinked ${subdir} from newlib"
    fi
done

# ============================================================
# Stage 1 — C-only compiler (needed to compile Newlib)
# ============================================================
STAGE1_STAMP="${GCC_SRC}/_build_stage1/.install_done"
if [[ -f "${STAGE1_STAMP}" ]]; then
    log_info "GCC stage-1 already built — skipping."
else
    log_info "Configuring GCC stage 1 (C only) …"
    mkdir -p "${GCC_SRC}/_build_stage1"
    cd "${GCC_SRC}/_build_stage1"

    ../configure \
        "${GCC_COMMON_FLAGS[@]}" \
        --enable-languages=c \
        2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Building GCC stage 1 (jobs=${MAKE_JOBS}) …"
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
    log_info "Configuring Newlib ${VER_NEWLIB} …"
    mkdir -p "${GCC_SRC}/_build_newlib"
    cd "${GCC_SRC}/_build_newlib"

    # Newlib is built as part of the GCC source tree (we symlinked it above).
    # We use a sub-configure that builds both newlib and libgloss.
    "${NEWLIB_SRC}/configure" \
        --prefix="${AP_PREFIX}" \
        --target="${TARGET}" \
        --enable-multilib \
        --enable-newlib-io-long-long \
        --enable-newlib-register-fini \
        --disable-newlib-supplied-syscalls \
        --disable-nls \
        2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Building Newlib (jobs=${MAKE_JOBS}) …"
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
    log_info "Configuring GCC stage 2 (C + C++) …"
    mkdir -p "${GCC_SRC}/_build_stage2"
    cd "${GCC_SRC}/_build_stage2"

    ../configure \
        "${GCC_COMMON_FLAGS[@]}" \
        --enable-languages=c,c++ \
        --with-headers="${AP_PREFIX}/${TARGET}/include" \
        2>&1 | tee -a "${AP_LOG}" >&2

    log_info "Building GCC stage 2 (jobs=${MAKE_JOBS}) …"
    make -j"${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}" >&2
    make install 2>&1 | tee -a "${AP_LOG}" >&2

    # libstdc++ headers & lib
    make -j"${MAKE_JOBS}" all-target-libstdc++-v3 2>&1 | tee -a "${AP_LOG}" >&2
    make install-target-libstdc++-v3 2>&1 | tee -a "${AP_LOG}" >&2

    touch "${STAGE2_STAMP}"
    log_ok "GCC stage 2 done."
fi

# ============================================================
# Sanity check
# ============================================================
log_info "Verifying arm-none-eabi toolchain …"
for tool in gcc g++ ar nm objcopy objdump ranlib strip; do
    bin="${TOOLCHAIN_BIN}/${TARGET}-${tool}"
    if [[ -x "${bin}" ]]; then
        ver=$("${bin}" --version 2>&1 | head -1)
        log_ok "  ${TARGET}-${tool}  →  ${ver}"
    else
        log_warn "  ${TARGET}-${tool} NOT found"
    fi
done

# Quick compile test
TMPDIR=$(mktemp -d)
cat > "${TMPDIR}/hello.c" << 'EOF'
int main(void) { return 0; }
EOF
if "${TOOLCHAIN_BIN}/${TARGET}-gcc" \
       -mcpu=cortex-m7 -mthumb -mfloat-abi=hard -mfpu=fpv5-d16 \
       -o "${TMPDIR}/hello.elf" "${TMPDIR}/hello.c" -nostartfiles 2>&1; then
    log_ok "Cross-compilation smoke test PASSED (Cortex-M7)."
else
    log_warn "Cross-compilation smoke test FAILED — check build log."
fi
rm -rf "${TMPDIR}"

log_ok "GCC + Newlib complete.  Proceed with 04_build_host_tools.sh"
