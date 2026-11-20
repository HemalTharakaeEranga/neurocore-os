#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Compiles standalone Mojo 1.2.0 CPU/SIMD kernels and the C-ABI shared library
# into /opt/ml/kernels/ after validating host x86-64-v3 SIMD capabilities.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOJO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${1:-${MOJO_DIR}/pixi.toml}"
OUT_DIR="${2:-/opt/ml/kernels}"

if command -v neuro >/dev/null 2>&1; then
    echo "==> Running x86-64-v3 ISA preflight check"
    neuro check --isa
fi

mkdir -p "${OUT_DIR}"

echo "==> Verifying Mojo 1.2.0 environment (${MANIFEST})"
pixi run --manifest-path "${MANIFEST}" mojo --version

echo "==> Compiling simd_matmul binary"
pixi run --manifest-path "${MANIFEST}" \
    mojo build "${MOJO_DIR}/kernels/simd_matmul.mojo" -o "${OUT_DIR}/simd_matmul"

echo "==> Compiling libneuro_tensor_bridge.so C-ABI shared library"
pixi run --manifest-path "${MANIFEST}" \
    mojo build --emit shared-lib "${MOJO_DIR}/kernels/tensor_bridge.mojo" \
    -o "${OUT_DIR}/libneuro_tensor_bridge.so"

echo "==> Running standalone Mojo 1.2 SIMD self-test"
"${OUT_DIR}/simd_matmul" --selftest
echo "==> Mojo kernels built cleanly in ${OUT_DIR}"
