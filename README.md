# ArduPilot Build Environment — Alpine Linux (compile-from-source)

## What this does

Installs a complete ArduPilot cross-compilation environment on a **fresh Alpine Linux** machine, compiling every major dependency from source.

### Goals (all verified in `08_build_ardupilot.sh`)

```bash
cd ardupilot
./waf configure              # SITL / native Linux
./waf all                    # all vehicles for SITL

./waf configure --board MatekH743
./waf copter                 # ArduCopter firmware for MatekH743 (STM32H743)
```

---

## Why compile from source on Alpine?

Alpine Linux uses **musl libc**, not glibc.  The pre-built ARM toolchain
tarballs from ARM Ltd (`gcc-arm-none-eabi-*-linux.tar.bz2`) are dynamically
linked against **glibc** and will fail with:

```
arm-none-eabi-gcc: error while loading shared libraries: libstdc++.so.6
```

Building GCC + binutils from source on Alpine produces a toolchain that is
natively linked against musl and runs without any compatibility layer.

---

## Script overview

| Script | Purpose |
|--------|---------|
| `config.env` | Shared version pins and helper functions — **sourced by all scripts** |
| `install_all.sh` | **Master orchestrator** — runs steps 0–8 in order |
| `00_bootstrap.sh` | `apk add` minimal host scaffold (gcc, make, wget, git, python3 …) |
| `01_build_gcc_prereqs.sh` | GMP → MPFR → MPC → ISL from source |
| `02_build_binutils.sh` | GNU Binutils for `arm-none-eabi` from source |
| `03_build_gcc_newlib.sh` | GCC 12 + Newlib (3-stage bare-metal cross-compiler) |
| `04_build_host_tools.sh` | cmake, ninja, ccache from source |
| `05_python_packages.sh` | Python packages via pip (empy<4, future, pymavlink …) |
| `06_clone_ardupilot.sh` | Clone ArduPilot + recursive submodule init |
| `07_setup_env.sh` | **Source this** to set PATH / env before using the toolchain |
| `08_build_ardupilot.sh` | Runs all four waf commands; verifies output |
| `09_troubleshoot.sh` | Diagnostic checks + suggested fixes |

---

## Quick start

```bash
# On a fresh Alpine Linux machine:
git clone <this-repo>   # or copy the directory
cd ardupilot-alpine

# Full automatic install (will ask for sudo when needed)
bash install_all.sh

# …  or step by step:
sudo bash 00_bootstrap.sh
bash 01_build_gcc_prereqs.sh
bash 02_build_binutils.sh
bash 03_build_gcc_newlib.sh         # ← longest step, ~1-2h on 4 cores
bash 04_build_host_tools.sh
bash 05_python_packages.sh
bash 06_clone_ardupilot.sh
bash 08_build_ardupilot.sh
```

### Resume from a specific step

```bash
bash install_all.sh --from 4    # skip steps 0-3
bash install_all.sh --only 5    # run only step 5
bash install_all.sh --skip-sitl # skip the slow ./waf all
```

---

## After installation

Add to `~/.bashrc` or `~/.profile`:

```bash
source /path/to/ardupilot-alpine/07_setup_env.sh
```

Then at any time:

```bash
cd ~/ardupilot
./waf configure --board MatekH743
./waf copter
# firmware: build/MatekH743/bin/arducopter.bin
```

---

## Versions compiled from source

| Component | Version | Purpose |
|-----------|---------|---------|
| GMP | 6.3.0 | GCC math prerequisite |
| MPFR | 4.2.1 | GCC math prerequisite |
| MPC | 1.3.1 | GCC math prerequisite |
| ISL | 0.26 | GCC loop optimiser (optional but recommended) |
| binutils | 2.40 | Assembler, linker, object tools for arm-none-eabi |
| GCC | 12.3.0 | C/C++ cross compiler for arm-none-eabi |
| Newlib | 4.3.0 | Bare-metal C library (target-side) |
| cmake | 3.28.3 | Build system (waf feature checks) |
| ninja | 1.11.1 | Build backend |
| ccache | 4.9.1 | Compiler cache (speeds up rebuilds 5-10×) |

Python packages are installed from PyPI via pip.

---

## Disk space requirements

| Stage | Approximate size |
|-------|-----------------|
| Bootstrap apk packages | ~500 MB |
| Source downloads | ~400 MB |
| Build artefacts (build dirs) | ~8 GB |
| Installed toolchain (`/opt/ap-toolchain`) | ~1.5 GB |
| ArduPilot repo + submodules | ~2 GB |
| ArduPilot build output | ~3 GB |
| **Total** | **~15 GB** |

---

## Troubleshooting

Run the diagnostic script:

```bash
bash 09_troubleshoot.sh
```

### Common issues

**`AttributeError: module 'em' has no attribute 'BUFFERED_OPT'`**  
empy 4.x is installed.  ArduPilot requires empy < 4.0:
```bash
pip3 install 'empy>=3.3.4,<4.0' --force-reinstall
```

**`Could not find the program ['arm-none-eabi-ar']`**  
Toolchain not in PATH:
```bash
source ./07_setup_env.sh
```

**GCC stage-2 build fails with `error: '__float128' is not supported`**  
This is a known issue on musl hosts with GCC 12.  Add `--disable-decimal-float`
and `--disable-fixed-point` to the stage-2 configure flags in
`03_build_gcc_newlib.sh`.

**waf configure reports wrong Python version**  
Set `WAF_PYTHON=$(which python3)` in your environment or
`source ./07_setup_env.sh`.

**Submodule checkout fails / partial download**  
```bash
git -C ~/ardupilot submodule update --init --recursive --jobs=4
```

---

## MatekH743 board notes

The MatekH743 uses an STM32H743 MCU (Cortex-M7, 480 MHz, 2 MB flash).
ArduPilot's waf will automatically select:
- CPU: `cortex-m7`
- FPU: `fpv5-d16`  (hard-float ABI)
- Flash script: embedded in board definition

The compiled firmware is at:
```
~/ardupilot/build/MatekH743/bin/arducopter.bin   ← flash via Betaflight/QGC
~/ardupilot/build/MatekH743/bin/arducopter        ← ELF for GDB debugging
```
