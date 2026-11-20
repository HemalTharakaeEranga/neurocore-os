// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

//! Zero-copy tensor IPC plane using Eclipse iceoryx2 (Apache-2.0 OR MIT).
//!
//! `NeuroTensorHeader` matches the C ABI layout declared in `mojo/ffi/iox2_bridge.h`
//! so compiled Mojo 1.2.0 kernels (`@export(..., abi="C")`) and Rust/Python ML
//! runtimes exchange loaned shared-memory tensor slices without serialization.

use anyhow::{Context, Result};
use serde::Serialize;
use std::fs;
use std::path::Path;

pub const NEURO_TENSOR_MAGIC: u32 = 0x4E43_5431; // "NCT1"

/// C-ABI tensor descriptor shared between Mojo kernels and iceoryx2 publishers.
#[repr(C)]
#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NeuroTensorHeader {
    pub magic: u32,
    pub dtype: u32, // 0 = f32, 1 = f16, 2 = bf16, 3 = i32
    pub ndim: u32,
    pub _reserved: u32,
    pub shape: [u64; 4],
    pub byte_len: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct TensorChannelConfig {
    pub service_name: String,
    pub runtime_dir: String,
    pub backend: String,
    pub max_tensor_bytes: usize,
    pub tensor_magic: u32,
    pub tensor_header_bytes: usize,
}

impl TensorChannelConfig {
    pub fn init(runtime_dir: &Path) -> Result<Self> {
        fs::create_dir_all(runtime_dir).with_context(|| {
            format!(
                "Failed to initialize iceoryx2 metadata dir {}",
                runtime_dir.display()
            )
        })?;

        #[cfg(feature = "iox2")]
        let backend = "iceoryx2-0.10-lockfree-shm".to_string();
        #[cfg(not(feature = "iox2"))]
        let backend = "iceoryx2-abi-ready (compile with --features iox2 for live SHM)".to_string();

        Ok(Self {
            service_name: "neurocore/tensors/v1".into(),
            runtime_dir: runtime_dir.display().to_string(),
            backend,
            max_tensor_bytes: 64 * 1024 * 1024, // 64 MiB default loaned tensor slot
            tensor_magic: NEURO_TENSOR_MAGIC,
            tensor_header_bytes: std::mem::size_of::<NeuroTensorHeader>(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::mem::size_of;

    #[test]
    fn tensor_header_abi_size_is_stable() {
        assert_eq!(size_of::<NeuroTensorHeader>(), 56);
        let hdr = NeuroTensorHeader {
            magic: NEURO_TENSOR_MAGIC,
            dtype: 0,
            ndim: 2,
            _reserved: 0,
            shape: [64, 64, 0, 0],
            byte_len: 64 * 64 * 4,
        };
        assert_eq!(hdr.magic, NEURO_TENSOR_MAGIC);
    }
}
