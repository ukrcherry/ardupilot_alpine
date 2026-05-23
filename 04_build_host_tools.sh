#!/usr/bin/env bash
# =============================================================================
# 04_build_host_tools.sh
# Build from source: cmake, ninja, ccache
#
# cmake  — ArduPilot's waf uses cmake internally for some feature checks
# ninja  — waf --jobs uses ninja as backend when available
# ccache — Dramatically speeds up incremental rebuilds
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"

section "04  Host tools — cmake / ninja / ccache"

require_cmd gcc
require_cmd make
require_cmd wget

# ============================================================
# cmake
# ============================================================
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${VER_CMAKE}/cmake-${VER_CMAKE}.tar.gz"
CMAKE_STAMP="${AP_SRC}/cmake-${VER_CMAKE}/_build/.install_done"

if [[ -f "${CMAKE_STAMP}" ]]; then
    log_info "cmake-${VER_CMAKE} already built — skipping."
else
    log_info "Fetching cmake ${VER_CMAKE} …"
    CMAKE_TARBALL=$(fetch "${CMAKE_URL}")
    CMAKE_SRC=$(extract_to "${CMAKE_TARBALL}" "cmake-${VER_CMAKE}")
    CMAKE_BUILD="${CMAKE_SRC}/_build"
    mkdir -p "${CMAKE_BUILD}"
    cd "${CMAKE_SRC}"

    log_info "Bootstrapping cmake (this uses cmake's own bootstrap script) …"
    # cmake bootstraps with its bundled version of cmake or with CC/CXX
    ./bootstrap \
        --prefix="${AP_PREFIX}" \
        --parallel="${MAKE_JOBS}" \
        --no-qt-gui \
        -- \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_USE_OPENSSL=ON \
        2>&1 | tee -a "${AP_LOG}"

    log_info "Building cmake (jobs=${MAKE_JOBS}) …"
    make -j"${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}"
    make install 2>&1 | tee -a "${AP_LOG}"

    touch "${CMAKE_STAMP}"
    log_ok "cmake-${VER_CMAKE} installed."
fi

CMAKE_VER_ACTUAL=$("${TOOLCHAIN_BIN}/cmake" --version | head -1)
log_ok "cmake: ${CMAKE_VER_ACTUAL}"

# ============================================================
# ninja
# ============================================================
NINJA_URL="https://github.com/ninja-build/ninja/archive/refs/tags/v${VER_NINJA}.tar.gz"
NINJA_STAMP="${AP_SRC}/ninja-${VER_NINJA}/_build/.install_done"

if [[ -f "${NINJA_STAMP}" ]]; then
    log_info "ninja-${VER_NINJA} already built — skipping."
else
    log_info "Fetching ninja ${VER_NINJA} …"
    NINJA_TARBALL=$(fetch "${NINJA_URL}")
    # GitHub tarballs extract to ninja-1.11.1/
    NINJA_SRC=$(extract_to "${NINJA_TARBALL}" "ninja-${VER_NINJA}")
    mkdir -p "${NINJA_SRC}/_build"
    cd "${NINJA_SRC}"

    log_info "Building ninja via cmake …"
    # ninja builds itself using cmake once cmake is present; fall back to
    # ./configure.py if cmake is not yet in PATH
    if command -v cmake &>/dev/null; then
        cmake -B _build \
              -DCMAKE_BUILD_TYPE=Release \
              -DCMAKE_INSTALL_PREFIX="${AP_PREFIX}" \
              2>&1 | tee -a "${AP_LOG}"
        cmake --build _build --parallel "${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}"
        cmake --install _build 2>&1 | tee -a "${AP_LOG}"
    else
        # Fallback: build with re2c if available, else bootstrap python script
        python3 configure.py --bootstrap 2>&1 | tee -a "${AP_LOG}"
        install -m755 ninja "${AP_PREFIX}/bin/"
    fi

    touch "${NINJA_STAMP}"
    log_ok "ninja-${VER_NINJA} installed."
fi

NINJA_VER_ACTUAL=$("${TOOLCHAIN_BIN}/ninja" --version)
log_ok "ninja: ${NINJA_VER_ACTUAL}"

# ============================================================
# ccache
# ============================================================
CCACHE_URL="https://github.com/ccache/ccache/releases/download/v${VER_CCACHE}/ccache-${VER_CCACHE}.tar.gz"
CCACHE_STAMP="${AP_SRC}/ccache-${VER_CCACHE}/_build/.install_done"

if [[ -f "${CCACHE_STAMP}" ]]; then
    log_info "ccache-${VER_CCACHE} already built — skipping."
else
    log_info "Fetching ccache ${VER_CCACHE} …"
    CCACHE_TARBALL=$(fetch "${CCACHE_URL}")
    CCACHE_SRC=$(extract_to "${CCACHE_TARBALL}" "ccache-${VER_CCACHE}")
    mkdir -p "${CCACHE_SRC}/_build"
    cd "${CCACHE_SRC}/_build"

    log_info "Configuring ccache …"
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="${AP_PREFIX}" \
        -DREDIS_STORAGE_BACKEND=OFF \
        2>&1 | tee -a "${AP_LOG}"

    log_info "Building ccache (jobs=${MAKE_JOBS}) …"
    cmake --build . --parallel "${MAKE_JOBS}" 2>&1 | tee -a "${AP_LOG}"
    cmake --install . 2>&1 | tee -a "${AP_LOG}"

    touch "${CCACHE_STAMP}"
    log_ok "ccache-${VER_CCACHE} installed."
fi

CCACHE_VER_ACTUAL=$("${TOOLCHAIN_BIN}/ccache" --version | head -1)
log_ok "ccache: ${CCACHE_VER_ACTUAL}"

# ============================================================
# ccache symlinks for the ARM cross compiler
# ArduPilot's build system looks for these in PATH
# ============================================================
log_info "Setting up ccache symlinks for ${TARGET} tools …"
CCACHE_DIR="${AP_PREFIX}/lib/ccache"
mkdir -p "${CCACHE_DIR}"

for tool in gcc g++ gcc-ar gcov gcc-nm gcc-ranlib; do
    LINK="${CCACHE_DIR}/${TARGET}-${tool}"
    if [[ ! -L "${LINK}" ]]; then
        ln -sf "${TOOLCHAIN_BIN}/ccache" "${LINK}"
        log_info "  created: ${LINK}"
    fi
done

# Also symlink native gcc/g++ for SITL builds
for tool in gcc g++; do
    LINK="${CCACHE_DIR}/${tool}"
    if [[ ! -L "${LINK}" ]]; then
        ln -sf "${TOOLCHAIN_BIN}/ccache" "${LINK}"
    fi
done

log_info "Add ccache symlinks to PATH (before toolchain bin):"
log_info "  export PATH=\"${CCACHE_DIR}:\${PATH}\""

log_ok "Host tools complete.  Proceed with 05_python_packages.sh"
