// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use serde::Serialize;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Serialize)]
pub struct TelemetrySnapshot {
    pub kernel_release: String,
    pub rust_telemetry_module: String,
    pub cgroup_slice_memory_current_bytes: Option<u64>,
    pub cgroup_slice_memory_high: Option<String>,
    pub cgroup_slice_memory_max: Option<String>,
    pub sched_ext_state: String,
    pub llama_socket_present: bool,
    pub dri_render_nodes: Vec<String>,
}

pub fn collect_snapshot() -> TelemetrySnapshot {
    let kernel_release = read_trimmed("/proc/sys/kernel/osrelease")
        .unwrap_or_else(|| "unknown".into());

    let rust_telemetry_module = read_trimmed("/sys/kernel/neurocore/status")
        .or_else(|| read_trimmed("/sys/module/neurocore_telemetry/initstate"))
        .unwrap_or_else(|| "unloaded".into());

    let slice_root = "/sys/fs/cgroup/neurocore.slice";
    let cgroup_slice_memory_current_bytes =
        read_trimmed(&format!("{}/memory.current", slice_root))
            .and_then(|s| s.parse::<u64>().ok());
    let cgroup_slice_memory_high = read_trimmed(&format!("{}/memory.high", slice_root));
    let cgroup_slice_memory_max = read_trimmed(&format!("{}/memory.max", slice_root));

    let sched_ext_state = read_trimmed("/sys/kernel/sched_ext/state")
        .unwrap_or_else(|| "unavailable".into());

    let llama_socket_present = Path::new("/run/neurocore/llama.sock").exists();

    let mut dri_render_nodes = Vec::new();
    if let Ok(entries) = fs::read_dir("/dev/dri") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("renderD") {
                dri_render_nodes.push(format!("/dev/dri/{}", name));
            }
        }
    }
    dri_render_nodes.sort();

    TelemetrySnapshot {
        kernel_release,
        rust_telemetry_module,
        cgroup_slice_memory_current_bytes,
        cgroup_slice_memory_high,
        cgroup_slice_memory_max,
        sched_ext_state,
        llama_socket_present,
        dri_render_nodes,
    }
}

fn read_trimmed(path: &str) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_string())
}
