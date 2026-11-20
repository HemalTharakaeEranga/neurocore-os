#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Builds llama.cpp v1.0.0 (MIT) with dynamic ggml backend loading
# (GGML_BACKEND_DL=ON), multi-ISA CPU variants (GGML_CPU_ALL_VARIANTS=ON),
# Vulkan compute (RADV/ANV/NVK), and optional AMD ROCm/HIP.
#
# Uses a private mktemp -d workspace (prevents CWE-377 /tmp race conditions)
# and installs shared libraries via `cp -a` to preserve symlinks.
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-v1.0.0}"
ENABLE_HIP="${ENABLE_HIP:-OFF}"
ENABLE_VULKAN="${ENABLE_VULKAN:-ON}"
PREFIX="${PREFIX:-/usr/local}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

if [[ ! "${LLAMA_TAG}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)?$ ]]; then
    echo "ERROR: Invalid LLAMA_TAG '${LLAMA_TAG}'" >&2
    exit 2
fi

BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/neurocore-llama.XXXXXX")"
chmod 0700 "${BUILD_ROOT}"
trap 'rm -rf "${BUILD_ROOT}"' EXIT

SRC_DIR="${BUILD_ROOT}/llama.cpp"
OBJ_DIR="${BUILD_ROOT}/build"

echo "==> Cloning ggml-org/llama.cpp (${LLAMA_TAG}) into isolated temp dir"
git -c protocol.version=2 clone --depth 1 --branch "${LLAMA_TAG}" \
    https://github.com/ggml-org/llama.cpp.git "${SRC_DIR}"

echo "==> Configuring llama.cpp (${LLAMA_TAG}, VULKAN=${ENABLE_VULKAN}, HIP=${ENABLE_HIP})"
cmake -S "${SRC_DIR}" -B "${OBJ_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DBUILD_SHARED_LIBS=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_BACKEND_DL=ON \
    -DGGML_CPU_ALL_VARIANTS=ON \
    -DGGML_VULKAN="${ENABLE_VULKAN}" \
    -DGGML_HIP="${ENABLE_HIP}" \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=ON \
    -DLLAMA_BUILD_SERVER=ON

echo "==> Building llama-server & llama-cli (-j${JOBS})"
cmake --build "${OBJ_DIR}" --target llama-server llama-cli -j "${JOBS}"

echo "==> Installing binaries and symlink-preserved shared libraries into ${PREFIX}"
install -d "${PREFIX}/bin" "${PREFIX}/lib"
install -m 0755 "${OBJ_DIR}/bin/llama-server" "${PREFIX}/bin/llama-server"
install -m 0755 "${OBJ_DIR}/bin/llama-cli" "${PREFIX}/bin/llama-cli"

shopt -s nullglob
for lib in "${OBJ_DIR}"/bin/libggml*.so* "${OBJ_DIR}"/bin/libllama*.so* \
           "${OBJ_DIR}"/src/libllama*.so* "${OBJ_DIR}"/ggml/src/libggml*.so*; do
    cp -a "${lib}" "${PREFIX}/lib/"
done
shopt -u nullglob

if command -v ldconfig >/dev/null 2>&1 && [[ "$(id -u)" -eq 0 ]]; then
    ldconfig
fi

echo "==> Verifying dynamic backend enumeration"
"${PREFIX}/bin/llama-cli" --list-devices || true
echo "==> llama.cpp ${LLAMA_TAG} installation complete."
