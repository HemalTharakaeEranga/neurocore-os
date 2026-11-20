# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Standalone Mojo 1.2.0 CPU/SIMD starter (def + comptime; zero MAX deps)

from sys import simd_width_of

comptime WIDTH = simd_width_of[DType.float32]()


def main():
    var a = SIMD[DType.float32, WIDTH](2.0)
    var b = SIMD[DType.float32, WIDTH](3.5)
    var c = a * b + 1.0
    print("NeuroCore Mojo 1.2 SIMD width=", WIDTH, " result[0]=", c[0])
