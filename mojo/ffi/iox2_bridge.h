/*
 * SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
 * SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
 *
 * C ABI contract bridging compiled Mojo 1.2.0 CPU/SIMD shared libraries
 * (`libneuro_tensor_bridge.so`) with Rust (`neurocore-daemon` + Eclipse iceoryx2).
 */

#ifndef NEUROCORE_IOX2_BRIDGE_H
#define NEUROCORE_IOX2_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NEURO_TENSOR_MAGIC 0x4E435431u /* "NCT1" */

typedef enum NeuroTensorDType {
    NEURO_DTYPE_F32 = 0,
    NEURO_DTYPE_F16 = 1,
    NEURO_DTYPE_BF16 = 2,
    NEURO_DTYPE_I32 = 3
} NeuroTensorDType;

/* Exact 56-byte C-ABI match with rust/neurocore-daemon/src/ipc_iox2.rs */
typedef struct NeuroTensorHeader {
    uint32_t magic;
    uint32_t dtype;
    uint32_t ndim;
    uint32_t reserved;
    uint64_t shape[4];
    uint64_t byte_len;
} NeuroTensorHeader;

/* In-place SIMD ReLU over loaned float32 buffer. Returns 0 on success. */
int32_t neuro_mojo_relu_f32(float *data, ptrdiff_t len_elems);

/* SIMD float32 matmul C[m,n] = A[m,k] * B[k,n]. Returns 0 on success. */
int32_t neuro_mojo_matmul_f32(
    const float *a,
    const float *b,
    float *c,
    ptrdiff_t m,
    ptrdiff_t n,
    ptrdiff_t k
);

#ifdef __cplusplus
}
#endif

#endif /* NEUROCORE_IOX2_BRIDGE_H */
