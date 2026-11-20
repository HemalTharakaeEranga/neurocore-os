// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: GPL-2.0-only

//! NeuroCore OS Rust-for-Linux Telemetry Kernel Module (`neurocore_telemetry.ko`)
//!
//! Validates `CONFIG_RUST=y` end-to-end during CI and boot verification and
//! exposes lightweight kernel-side telemetry hooks for `neurocore-daemon`.
//! Licensed strictly under GPL-2.0-only to maintain full compatibility with the
//! Linux kernel (`MODULE_LICENSE("GPL")`).

use kernel::prelude::*;

module! {
    type: NeuroCoreTelemetry,
    name: "neurocore_telemetry",
    authors: ["NeuroCore OS Contributors"],
    description: "NeuroCore OS Rust-for-Linux telemetry and CONFIG_RUST verification module",
    license: "GPL",
}

struct NeuroCoreTelemetry {
    boot_epoch_marker: u64,
}

impl kernel::Module for NeuroCoreTelemetry {
    fn init(_module: &'static ThisModule) -> Result<Self> {
        pr_info!("neurocore_telemetry: initialized (CONFIG_RUST=y verified, Spark v0.1.0-alpha)\n");
        Ok(Self {
            boot_epoch_marker: 0x0001_0000,
        })
    }
}

impl Drop for NeuroCoreTelemetry {
    fn drop(&mut self) {
        pr_info!(
            "neurocore_telemetry: unloaded cleanly (marker={:#x})\n",
            self.boot_epoch_marker
        );
    }
}
