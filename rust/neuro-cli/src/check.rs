// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use anyhow::{Result, bail};
use serde::Serialize;
use std::env;
use std::fs;
use std::path::Path;
use std::process::Command;

/// Required x86-64-v3 CPUID flags for standalone Mojo 1.2.0 CPU/SIMD execution.
const X86_64_V3_FLAGS: &[&str] = &[
    "avx", "avx2", "bmi1", "bmi2", "f16c", "fma", "movbe", "xsave",
];

#[derive(Debug, Serialize)]
pub struct HardwareReport {
    pub arch: String,
    pub x86_64_v3_ready: bool,
    pub missing_isa_flags: Vec<String>,
    pub total_ram_gib: f64,
    pub ram_meets_mojo_floor: bool,
    pub c_linker_found: Option<String>,
    pub virtualized_env: Option<String>,
    pub amd_kfd_present: bool,
    pub dri_render_nodes: Vec<String>,
    pub intel_i915_detected: bool,
    pub recommended_env: Vec<(String, String)>,
    pub cgroup_v2_active: bool,
    pub sched_ext_state: String,
    pub llama_socket_ready: bool,
    pub daemon_socket_ready: bool,
    pub apparmor_enabled: bool,
    pub unpriv_bpf_disabled: bool,
    pub kernel_lockdown: String,
}

pub fn collect_report() -> HardwareReport {
    let arch = std::env::consts::ARCH.to_string();
    let (x86_64_v3_ready, missing_isa_flags) = check_cpu_isa(&arch);
    let total_ram_gib = read_total_ram_gib();
    let c_linker_found = ["gcc", "clang", "clang-19"]
        .into_iter()
        .find(|bin| command_exists(bin))
        .map(String::from);

    let virtualized_env = detect_hypervisor();
    let amd_kfd_present = Path::new("/dev/kfd").exists();
    let dri_render_nodes = list_dri_render_nodes();
    let intel_i915_detected = detect_intel_i915();

    let mut recommended_env = Vec::new();
    if intel_i915_detected {
        recommended_env.push(("GGML_VK_SERIALIZE_SUBMISSIONS".into(), "1".into()));
    }
    if virtualized_env.is_some() && !amd_kfd_present {
        recommended_env.push(("GGML_VK_VISIBLE_DEVICES".into(), "".into()));
    }

    let cgroup_v2_active = Path::new("/sys/fs/cgroup/cgroup.controllers").exists();
    let sched_ext_state = read_sched_ext_state();
    let llama_socket_ready = Path::new("/run/neurocore/llama.sock").exists();
    let daemon_socket_ready = Path::new("/run/neurocore/daemon.sock").exists();

    let apparmor_enabled = fs::read_to_string("/sys/module/apparmor/parameters/enabled")
        .map(|s| s.trim() == "Y")
        .unwrap_or(false);
    let unpriv_bpf_disabled = fs::read_to_string("/proc/sys/kernel/unprivileged_bpf_disabled")
        .map(|s| matches!(s.trim(), "1" | "2"))
        .unwrap_or(false);
    let kernel_lockdown = fs::read_to_string("/sys/kernel/security/lockdown")
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "unavailable".into());

    HardwareReport {
        arch,
        x86_64_v3_ready,
        missing_isa_flags,
        total_ram_gib,
        ram_meets_mojo_floor: total_ram_gib >= 7.5,
        c_linker_found,
        virtualized_env,
        amd_kfd_present,
        dri_render_nodes,
        intel_i915_detected,
        recommended_env,
        cgroup_v2_active,
        sched_ext_state,
        llama_socket_ready,
        daemon_socket_ready,
        apparmor_enabled,
        unpriv_bpf_disabled,
        kernel_lockdown,
    }
}

pub fn run(isa_only: bool, run_bench: bool, as_json: bool) -> Result<()> {
    let report = collect_report();

    if as_json {
        println!("{}", serde_json::to_string_pretty(&report)?);
    } else {
        println!("=== NeuroCore OS v0.1.0-alpha ('Spark') Hardware & Security Check ===");
        println!("Architecture        : {}", report.arch);
        println!(
            "x86-64-v3 / SIMD    : {} {}",
            if report.x86_64_v3_ready { "READY" } else { "MISSING FLAGS" },
            if report.missing_isa_flags.is_empty() {
                String::new()
            } else {
                format!("(missing: {})", report.missing_isa_flags.join(", "))
            }
        );
        println!(
            "System Memory       : {:.2} GiB ({})",
            report.total_ram_gib,
            if report.ram_meets_mojo_floor { "OK >= 8 GiB floor" } else { "LOW < 8 GiB" }
        );
        println!(
            "C Linker            : {}",
            report.c_linker_found.as_deref().unwrap_or("MISSING (gcc/clang required for Mojo)")
        );
        println!(
            "Virtualization      : {}",
            report.virtualized_env.as_deref().unwrap_or("Bare metal / None detected")
        );
        println!(
            "AMD ROCm (/dev/kfd) : {}",
            if report.amd_kfd_present { "Present" } else { "Not detected" }
        );
        println!(
            "DRM Render Nodes    : {}",
            if report.dri_render_nodes.is_empty() {
                "None (CPU / Lavapipe fallback)".to_string()
            } else {
                report.dri_render_nodes.join(", ")
            }
        );
        println!(
            "Unified cgroup v2   : {}",
            if report.cgroup_v2_active { "Active" } else { "Inactive" }
        );
        println!("sched_ext State     : {}", report.sched_ext_state);
        println!(
            "Security Posture    : AppArmor={} unpriv_bpf_disabled={} lockdown={}",
            report.apparmor_enabled, report.unpriv_bpf_disabled, report.kernel_lockdown
        );
        println!(
            "IPC Sockets         : daemon={} llama={}",
            if report.daemon_socket_ready { "UP" } else { "DOWN" },
            if report.llama_socket_ready { "UP" } else { "DOWN" }
        );

        if !report.recommended_env.is_empty() {
            println!("Recommended Env Mitigations:");
            for (k, v) in &report.recommended_env {
                println!("  export {}=\"{}\"", k, v);
            }
        }
    }

    if isa_only && !report.x86_64_v3_ready {
        bail!(
            "Host CPU lacks required x86-64-v3 flags ({}) for Mojo 1.2.0 CPU/SIMD. \
             In VirtualBox 7.2+, verify AVX2 passthrough is enabled.",
            report.missing_isa_flags.join(", ")
        );
    }

    if run_bench {
        println!("\n==> Running neuro-bench smoke suite...");
        let status = Command::new("neuro-bench").arg("--all").status()?;
        if !status.success() {
            bail!("neuro-bench exited with status {}", status);
        }
    }

    Ok(())
}

fn check_cpu_isa(arch: &str) -> (bool, Vec<String>) {
    if arch == "aarch64" {
        return (true, Vec::new());
    }
    let Ok(cpuinfo) = fs::read_to_string("/proc/cpuinfo") else {
        return (false, vec!["/proc/cpuinfo-unreadable".into()]);
    };
    let flags_line = cpuinfo
        .lines()
        .find(|line| line.starts_with("flags"))
        .and_then(|line| line.split(':').nth(1))
        .unwrap_or("");
    let flags: Vec<&str> = flags_line.split_whitespace().collect();

    let mut missing = Vec::new();
    for req in X86_64_V3_FLAGS {
        if !flags.contains(req) {
            missing.push((*req).to_string());
        }
    }
    if !flags.contains(&"abm") && !flags.contains(&"lzcnt") {
        missing.push("lzcnt/abm".to_string());
    }
    (missing.is_empty(), missing)
}

fn read_total_ram_gib() -> f64 {
    let Ok(meminfo) = fs::read_to_string("/proc/meminfo") else {
        return 0.0;
    };
    for line in meminfo.lines() {
        if let Some(rest) = line.strip_prefix("MemTotal:") {
            let kb: f64 = rest
                .split_whitespace()
                .next()
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.0);
            return kb / (1024.0 * 1024.0);
        }
    }
    0.0
}

fn detect_hypervisor() -> Option<String> {
    if let Ok(product) = fs::read_to_string("/sys/class/dmi/id/product_name") {
        let p = product.trim();
        if p.contains("VirtualBox") {
            return Some("VirtualBox".into());
        }
        if p.contains("QEMU") || p.contains("Standard PC") || p.contains("KVM") {
            return Some("QEMU/KVM".into());
        }
    }
    if let Ok(cpuinfo) = fs::read_to_string("/proc/cpuinfo") {
        if cpuinfo.contains("hypervisor") {
            return Some("Hypervisor (generic)".into());
        }
    }
    None
}

fn list_dri_render_nodes() -> Vec<String> {
    let mut nodes = Vec::new();
    if let Ok(entries) = fs::read_dir("/dev/dri") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("renderD") {
                nodes.push(format!("/dev/dri/{}", name));
            }
        }
    }
    nodes.sort();
    nodes
}

fn detect_intel_i915() -> bool {
    Path::new("/sys/module/i915").exists()
}

fn read_sched_ext_state() -> String {
    if let Ok(state) = fs::read_to_string("/sys/kernel/sched_ext/state") {
        let ops = fs::read_to_string("/sys/kernel/sched_ext/root/ops")
            .unwrap_or_else(|_| "none".into());
        return format!("{} (ops={})", state.trim(), ops.trim());
    }
    "Unavailable (CONFIG_SCHED_CLASS_EXT not active)".into()
}

/// Pure-Rust PATH binary lookup with zero shell invocation (avoids CWE-78).
fn command_exists(name: &str) -> bool {
    if name.is_empty() || name.contains('/') || name.contains('\\') {
        return false;
    }
    let Some(path_var) = env::var_os("PATH") else {
        return false;
    };
    for dir in env::split_paths(&path_var) {
        let candidate = dir.join(name);
        if let Ok(meta) = fs::metadata(&candidate) {
            if meta.is_file() {
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    if meta.permissions().mode() & 0o111 != 0 {
                        return true;
                    }
                }
                #[cfg(not(unix))]
                {
                    return true;
                }
            }
        }
    }
    false
}
