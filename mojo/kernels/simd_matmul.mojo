# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# Standalone Mojo 1.2.0 CPU/SIMD Matrix Multiplication Kernel.
# Uses modern Mojo 1.2 syntax (`def`, `comptime`) with zero Modular MAX
# dependencies so this kernel remains 100% OSI-approved Apache-2.0.

from sys import argv, simd_width_of
from memory import UnsafePointer
from algorithm import vectorize

comptime DTYPE = DType.float32
comptime SIMD_WIDTH = simd_width_of[DTYPE]()


def simd_matmul_f32(
    a: UnsafePointer[Scalar[DTYPE]],
    b: UnsafePointer[Scalar[DTYPE]],
    c: UnsafePointer[Scalar[DTYPE]],
    m: Int,
    n: Int,
    k: Int,
):
    """Vectorized CPU/SIMD matrix multiplication C[m, n] = A[m, k] * B[k, n]."""
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

            vectorize[vec_fma, SIMD_WIDTH](n)


def run_selftest() raises:
    comptime N = 64
    var total = N * N
    var a = UnsafePointer[Scalar[DTYPE]].alloc(total)
    var b = UnsafePointer[Scalar[DTYPE]].alloc(total)
    var c = UnsafePointer[Scalar[DTYPE]].alloc(total)

    for idx in range(total):
        a[idx] = 1.5
        b[idx] = 2.0
        c[idx] = 0.0

    simd_matmul_f32(a, b, c, N, N, N)

    var expected: Float32 = Float32(N) * 3.0
    var max_err: Float32 = 0.0
    for idx in range(total):
        var diff = c[idx] - expected
        if diff < 0.0:
            diff = -diff
        if diff > max_err:
            max_err = diff

    a.free()
    b.free()
    c.free()

    print(
        "[neurocore-mojo] 64x64 f32 SIMD matmul (width=",
        SIMD_WIDTH,
        ") max_err=",
        max_err,
    )
    if max_err > 1e-3:
        raise Error("Mojo 1.2 SIMD matmul exceeded tolerance 1e-3")


def main() raises:
    var args = argv()
    var selftest = False
    for i in range(len(args)):
        if String(args[i]) == "--selftest":
            selftest = True

    if selftest:
        run_selftest()
        print("[neurocore-mojo] selftest PASS")
    else:
        run_selftest()
