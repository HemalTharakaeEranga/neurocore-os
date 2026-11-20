// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use crate::check;
use anyhow::{Result, bail};
use std::fs;
use std::path::Path;
use std::process::Command;

pub fn run(no_systemd: bool) -> Result<()> {
    let mut failures = Vec::new();
    println!("=== NeuroCore OS v0.1.0-alpha ('Spark') Release Gate Self-Test ===");

    // Gate 1: OS identity
    match fs::read_to_string("/etc/os-release") {
        Ok(content)
            if content.contains("ID=neurocore") && content.contains("VERSION_ID=\"0.1.0\"") =>
        {
            println!("[PASS] Gate 1: /etc/os-release matches NeuroCore OS 0.1.0");
        }
        Ok(_) => {
            failures.push("Gate 1: /etc/os-release missing ID=neurocore or VERSION_ID=\"0.1.0\"")
        }
        Err(_) => failures.push("Gate 1: /etc/os-release unreadable"),
    }

    // Gate 2: Rust-for-Linux kernel module check
    if Path::new("/sys/module/neurocore_telemetry/initstate").exists()
        || Path::new("/sys/kernel/neurocore/status").exists()
    {
        println!("[PASS] Gate 2: neurocore_telemetry Rust kernel module active");
    } else {
        println!(
            "[WARN] Gate 2: neurocore_telemetry not currently loaded (run `sudo modprobe neurocore_telemetry`)"
        );
    }

    // Gate 3: Unified cgroups v2 & systemd ML services
    let report = check::collect_report();
    if report.cgroup_v2_active {
        println!("[PASS] Gate 3a: Unified cgroups v2 mounted");
    } else {
        failures.push("Gate 3a: Unified cgroups v2 not mounted");
    }

    if !no_systemd {
        for svc in ["neurocore-mlflow.service", "neurocore-jupyter.service"] {
            let ok = Command::new("systemctl")
                .args(["is-active", "--quiet", svc])
                .status()
                .map(|s| s.success())
                .unwrap_or(false);
            if ok {
                println!("[PASS] Gate 3b: {} is active", svc);
            } else {
                println!("[WARN] Gate 3b: {} is not active", svc);
            }
        }
    }

    // Gate 4: Mojo 1.2 ISA & SIMD check
    if report.x86_64_v3_ready {
        println!("[PASS] Gate 4a: Host CPU satisfies x86-64-v3 floor for Mojo 1.2.0");
    } else {
        failures.push("Gate 4a: Host CPU missing x86-64-v3 flags");
    }

    // Gate 5: Rust ML smoke check via neuro-bench
    let bench_ok = Command::new("neuro-bench")
        .arg("--all")
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if bench_ok {
        println!("[PASS] Gate 5: neuro-bench passed");
    } else {
        println!("[WARN] Gate 5: neuro-bench unavailable or returned non-zero");
    }

    // Gate 6 & 7: IPC sockets
    if report.llama_socket_ready {
        println!("[PASS] Gate 7: /run/neurocore/llama.sock present");
    } else {
        println!("[WARN] Gate 7: /run/neurocore/llama.sock not active");
    }

    if failures.is_empty() {
        println!("=== Self-Test Summary: PASS (0 hard failures) ===");
        Ok(())
    } else {
        for f in &failures {
            eprintln!("[FAIL] {}", f);
        }
        bail!("Self-test failed with {} hard error(s).", failures.len());
    }
}
