# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# C-ABI shared-library bridge (`libneuro_tensor_bridge.so`) allowing Rust
# (`neurocore-daemon` + Eclipse iceoryx2) and Python (PyTorch) to invoke
# compiled Mojo 1.2.0 CPU/SIMD kernels directly on loaned shared-memory buffers
# with defensive dimension & integer-overflow bounds checks.

from sys import simd_width_of
from memory import UnsafePointer
from algorithm import vectorize

comptime F32_WIDTH = simd_width_of[DType.float32]()
# Hard safety limits preventing integer overflow & OOB writes across C-ABI FFI
comptime MAX_TENSOR_ELEMS = 268_435_456  # 1 GiB of float32 elements
comptime MAX_MATMUL_DIM = 16_384


@export("neuro_mojo_relu_f32", abi="C")
def neuro_mojo_relu_f32(
    data: UnsafePointer[Float32],
    len_elems: Int,
) -> Int32:
    """In-place SIMD ReLU over a loaned float32 shared-memory tensor slice."""
    if not data or len_elems < 0 or len_elems > MAX_TENSOR_ELEMS:
        return -1

    def vec_relu[width: Int](idx: Int):
        var v = data.load[width=width](idx)
        var zero = SIMD[DType.float32, width](0.0)
        data.store[width=width](idx, v.max(zero))

    vectorize[vec_relu, F32_WIDTH](len_elems)
    return 0


@export("neuro_mojo_matmul_f32", abi="C")
def neuro_mojo_matmul_f32(
    a: UnsafePointer[Float32],
    b: UnsafePointer[Float32],
    c: UnsafePointer[Float32],
    m: Int,
    n: Int,
    k: Int,
) -> Int32:
    """C-ABI SIMD float32 matrix multiplication for zero-copy iceoryx2 buffers."""
    if (
        not a
        or not b
        or not c
        or m <= 0
        or n <= 0
        or k <= 0
        or m > MAX_MATMUL_DIM
        or n > MAX_MATMUL_DIM
        or k > MAX_MATMUL_DIM
    ):
        return -1

    # Guard against product overflow exceeding shared-memory slot bounds
    if m * n > MAX_TENSOR_ELEMS or m * k > MAX_TENSOR_ELEMS or k * n > MAX_TENSOR_ELEMS:
        return -2

    for i in range(m):
        for j in range(n):
            c[i * n + j] = 0.0
        for p in range(k):
            var a_val = a[i * k + p]
            var row_b = b + p * n
            var row_c = c + i * n

            def vec_fma[width: Int](col: Int):
                var bv = row_b.load[width=width](col)
                var cv = row_c.load[width=width](col)
                row_c.store[width=width](col, cv + a_val * bv)

            vectorize[vec_fma, F32_WIDTH](n)

    return 0
