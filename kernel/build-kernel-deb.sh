#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Configures, patches, injects the NeuroCore CLUT224 boot logo, builds Debian
# kernel packages (bindeb-pkg) with LLVM=1 + CONFIG_RUST=y using Debian's system
# rustc 1.85, builds the out-of-tree neurocore_telemetry.ko Rust module, and
# stages resulting .deb packages in mkosi/mkosi.packages/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TRACK="lts"
VERSION="6.18.64"
ARCH="x86_64"
SRC_DIR="${SCRIPT_DIR}/src/linux-${VERSION}"
BUILD_DIR="${SCRIPT_DIR}/build/${TRACK}-${ARCH}"
OUT_DIR="${REPO_ROOT}/mkosi/mkosi.packages"
RUSTC_BIN="${KERNEL_RUSTC:-/usr/bin/rustc}"
BINDGEN_BIN="${KERNEL_BINDGEN:-/usr/bin/bindgen}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --track)     TRACK="$2"; shift 2 ;;
        --version)   VERSION="$2"; shift 2 ;;
        --arch)      ARCH="$2"; shift 2 ;;
        --src-dir)   SRC_DIR="$2"; shift 2 ;;
        --build-dir) BUILD_DIR="$2"; shift 2 ;;
        --out-dir)   OUT_DIR="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "${BUILD_DIR}" "${OUT_DIR}"

if [[ ! -d "${SRC_DIR}" ]]; then
    echo "ERROR: Kernel source directory not found: ${SRC_DIR}" >&2
    exit 1
fi

# 1. Inject NeuroCore CLUT224 framebuffer boot logo if generated
LOGO_PPM="${REPO_ROOT}/branding/generated/kernel/logo_linux_clut224.ppm"
if [[ -f "${LOGO_PPM}" ]]; then
    echo "==> Injecting custom 224-color boot logo into drivers/video/logo/logo_linux_clut224.ppm"
    cp -f "${LOGO_PPM}" "${SRC_DIR}/drivers/video/logo/logo_linux_clut224.ppm"
else
    echo "WARNING: ${LOGO_PPM} not found; run 'make branding' first to embed the NeuroCore boot logo." >&2
fi

# 2. Apply tracked GPLv2 kernel patches cleanly (idempotent marker)
PATCH_STAMP="${SRC_DIR}/.neurocore-patches-applied"
if [[ ! -f "${PATCH_STAMP}" ]]; then
    for patch_file in "${SCRIPT_DIR}"/patches/*.patch; do
        [[ -e "${patch_file}" ]] || continue
        echo "==> Checking patch: $(basename "${patch_file}")"
        if patch -d "${SRC_DIR}" -p1 --dry-run --forward --silent < "${patch_file}"; then
            patch -d "${SRC_DIR}" -p1 --forward < "${patch_file}"
        else
            echo "    [SKIP] Patch $(basename "${patch_file}") already applied or context changed for ${VERSION}; review manually."
        fi
    done
    touch "${PATCH_STAMP}"
fi

# 3. Resolve matched Clang + LLD + LLVM toolchain and align LIBCLANG_PATH for bindgen
LLVM_ARG="${KERNEL_LLVM:-}"
if [[ -z "${LLVM_ARG}" ]]; then
    if command -v clang >/dev/null 2>&1 && command -v ld.lld >/dev/null 2>&1; then
        LLVM_ARG="1"
    else
        for v in 22 21 20 19 18; do
            if command -v "clang-${v}" >/dev/null 2>&1 && command -v "ld.lld-${v}" >/dev/null 2>&1; then
                LLVM_ARG="-${v}"
                break
            fi
        done
    fi
fi
if [[ -z "${LLVM_ARG}" ]]; then
    echo "ERROR: Matched clang + ld.lld toolchain not found (install 'clang lld llvm' or versioned 'clang-N lld-N llvm-N')." >&2
    exit 1
fi

CLANG_BIN="clang"
if [[ "${LLVM_ARG}" == -* ]]; then
    CLANG_BIN="clang${LLVM_ARG}"
fi
CLANG_MAJOR="$("${CLANG_BIN}" --version | sed -n 's/.*clang version \([0-9][0-9]*\)\..*/\1/p' | head -n 1 || true)"
if [[ -z "${LIBCLANG_PATH:-}" && -n "${CLANG_MAJOR}" && -d "/usr/lib/llvm-${CLANG_MAJOR}/lib" ]]; then
    if compgen -G "/usr/lib/llvm-${CLANG_MAJOR}/lib/libclang*.so*" >/dev/null 2>&1; then
        export LIBCLANG_PATH="/usr/lib/llvm-${CLANG_MAJOR}/lib"
    fi
fi
export LLVM="${LLVM_ARG}"
export RUSTC="${RUSTC_BIN}"
export BINDGEN="${BINDGEN_BIN}"

# Verify Rust-for-Linux availability with system rustc (isolated from /opt/ml rustup 1.100)
echo "==> Verifying make LLVM=${LLVM_ARG} rustavailable with RUSTC=${RUSTC_BIN} (${CLANG_BIN} v${CLANG_MAJOR:-?}, LIBCLANG_PATH=${LIBCLANG_PATH:-auto})"
make -C "${SRC_DIR}" O="${BUILD_DIR}" LLVM="${LLVM_ARG}" RUSTC="${RUSTC_BIN}" BINDGEN="${BINDGEN_BIN}" rustavailable

# 4. Generate deterministic base .config and merge NeuroCore Kconfig fragments
echo "==> Merging NeuroCore Kconfig fragments (arch=${ARCH}, track=${TRACK})"
if [[ "${ARCH}" == "arm64" ]]; then
    make -C "${SRC_DIR}" O="${BUILD_DIR}" ARCH=arm64 LLVM="${LLVM_ARG}" RUSTC="${RUSTC_BIN}" BINDGEN="${BINDGEN_BIN}" defconfig
    FRAGMENTS=("${SCRIPT_DIR}/configs/neurocore_arm64.fragment")
else
    make -C "${SRC_DIR}" O="${BUILD_DIR}" LLVM="${LLVM_ARG}" RUSTC="${RUSTC_BIN}" BINDGEN="${BINDGEN_BIN}" defconfig
    FRAGMENTS=("${SCRIPT_DIR}/configs/neurocore_x86_64.fragment")
fi

if [[ "${TRACK}" == "next" ]]; then
    FRAGMENTS+=("${SCRIPT_DIR}/configs/neurocore_next_7x.fragment")
fi

KCONFIG_CONFIG="${BUILD_DIR}/.config" \
    "${SRC_DIR}/scripts/kconfig/merge_config.sh" -m -O "${BUILD_DIR}" "${BUILD_DIR}/.config" "${FRAGMENTS[@]}"

make -C "${SRC_DIR}" O="${BUILD_DIR}" LLVM="${LLVM_ARG}" RUSTC="${RUSTC_BIN}" BINDGEN="${BINDGEN_BIN}" olddefconfig

# Assert critical functional AND KSPP security Kconfig flags remained enabled after olddefconfig
for flag in \
    CONFIG_RUST=y \
    CONFIG_SCHED_CLASS_EXT=y \
    CONFIG_SQUASHFS_ZSTD=y \
    CONFIG_LOGO_LINUX_CLUT224=y \
    CONFIG_SECURITY_LANDLOCK=y \
    CONFIG_SECURITY_APPARMOR=y \
    CONFIG_BPF_UNPRIV_DEFAULT_OFF=y \
    CONFIG_HARDENED_USERCOPY=y \
    CONFIG_FORTIFY_SOURCE=y \
    CONFIG_STACKPROTECTOR_STRONG=y; do
    if ! grep -qx "${flag}" "${BUILD_DIR}/.config"; then
        echo "ERROR: Mandatory Kconfig option missing after olddefconfig: ${flag}" >&2
        exit 1
    fi
done

# 5. Build deterministic Debian kernel packages (linux-image + linux-headers)
# Keep LOCALVERSION empty because CONFIG_LOCALVERSION="-neurocore" is already set in Kconfig.
export KBUILD_BUILD_TIMESTAMP="@${SOURCE_DATE_EPOCH:-1763664000}"
export KBUILD_BUILD_USER="neurocore"
export KBUILD_BUILD_HOST="build.neurocore-os.org"
export LOCALVERSION=""
export KDEB_PKGVERSION="${VERSION}-neurocore1"

echo "==> Compiling Linux ${VERSION}-neurocore with LLVM=${LLVM_ARG} (-j${JOBS})"
make -C "${SRC_DIR}" O="${BUILD_DIR}" \
    LLVM="${LLVM_ARG}" \
    RUSTC="${RUSTC_BIN}" \
    BINDGEN="${BINDGEN_BIN}" \
    -j"${JOBS}" \
    bindeb-pkg

# 6. Build out-of-tree Rust-for-Linux telemetry kernel module
echo "==> Building out-of-tree Rust kernel module: neurocore_telemetry.ko"
make -C "${SCRIPT_DIR}/rust-modules/neurocore_telemetry" \
    KDIR="${BUILD_DIR}" \
    LLVM="${LLVM_ARG}" \
    RUSTC="${RUSTC_BIN}" \
    BINDGEN="${BINDGEN_BIN}"

KREL="$(cat "${BUILD_DIR}/include/config/kernel.release" 2>/dev/null || echo "${VERSION}-neurocore")"
MOD_DEST="${REPO_ROOT}/mkosi/mkosi.extra/usr/lib/modules/${KREL}/extra"
mkdir -p "${MOD_DEST}"
cp -f "${SCRIPT_DIR}/rust-modules/neurocore_telemetry/neurocore_telemetry.ko" "${MOD_DEST}/"

# 7. Stage generated runtime kernel .deb packages (excluding multi-GB -dbg) for mkosi
echo "==> Staging kernel .deb packages into ${OUT_DIR}"
find "${SCRIPT_DIR}/build" -maxdepth 2 -type f -name 'linux-*.deb' ! -name '*-dbg_*.deb' -exec cp -vf {} "${OUT_DIR}/" \;
cp -f "${BUILD_DIR}/.config" "${OUT_DIR}/config-${KREL}"

echo "==> Kernel build completed successfully."
