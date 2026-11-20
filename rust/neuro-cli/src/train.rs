// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use crate::check;
use anyhow::{Context, Result, bail};
use std::fs;
use std::path::Path;
use std::process::Command;

pub fn run(target: &str, sched_mode: &str, cpu_only: bool, extra_args: &[String]) -> Result<()> {
    if target.is_empty() || target.starts_with('-') {
        bail!(
            "Invalid training target '{}': path must not be empty or begin with '-'.",
            target
        );
    }

    let report = check::collect_report();
    let target_path = Path::new(target);
    let canonical = fs::canonicalize(target_path)
        .with_context(|| format!("Target '{}' does not exist or cannot be accessed", target))?;

    if sched_mode != "none" {
        try_switch_scheduler(sched_mode);
    }

    let mut cmd = if target.ends_with(".mojo") && canonical.is_file() {
        if !report.x86_64_v3_ready {
            bail!(
                "Cannot execute Mojo kernel '{}': host CPU lacks x86-64-v3 flags ({}).",
                target,
                report.missing_isa_flags.join(", ")
            );
        }
        let mut c = Command::new("pixi");
        c.args([
            "run",
            "--manifest-path",
            "/opt/ml/envs/mojo/pixi.toml",
            "mojo",
            "run",
        ])
        .arg(&canonical);
        c
    } else if target.ends_with(".py") && canonical.is_file() {
        let py = if Path::new("/opt/ml/envs/python-ml/.venv/bin/python").exists() {
            "/opt/ml/envs/python-ml/.venv/bin/python"
        } else {
            "python3"
        };
        let mut c = Command::new(py);
        c.arg("--").arg(&canonical);
        c
    } else if canonical.is_dir() && canonical.join("Cargo.toml").is_file() {
        let mut c = Command::new("cargo");
        c.args(["run", "--release", "--manifest-path"])
            .arg(canonical.join("Cargo.toml"));
        c
    } else {
        bail!(
            "Unsupported target '{}'. Expected an existing .py file, .mojo file, or Cargo project directory.",
            target
        );
    };

    // Wire loopback MLflow tracking endpoint by default
    cmd.env("MLFLOW_TRACKING_URI", "http://127.0.0.1:5000");

    if cpu_only {
        cmd.env("NEUROCORE_FORCE_CPU", "1");
        cmd.env("GGML_VK_VISIBLE_DEVICES", "");
        cmd.env("CUDA_VISIBLE_DEVICES", "");
        cmd.env("HIP_VISIBLE_DEVICES", "");
    } else {
        for (k, v) in &report.recommended_env {
            cmd.env(k, v);
        }
    }

    if !extra_args.is_empty() {
        cmd.arg("--").args(extra_args);
    }

    println!(
        "==> Launching '{}' (cpu_only={}, sched={})",
        canonical.display(),
        cpu_only,
        sched_mode
    );
    let status = cmd
        .status()
        .with_context(|| format!("Failed to spawn training process for '{}'", target))?;

    if !status.success() {
        bail!("Target '{}' exited with status {}", target, status);
    }
    Ok(())
}

fn try_switch_scheduler(mode: &str) {
    let scx_mode = match mode.to_lowercase().as_str() {
        "lowlatency" | "low-latency" => "lowlatency",
        "server" | "throughput" => "server",
        "powersave" | "power-save" => "powersave",
        _ => "auto",
    };
    if let Ok(status) = Command::new("scxctl").args(["switch", "-m", scx_mode]).status() {
        if status.success() {
            println!("==> sched_ext switched to mode '{}'", scx_mode);
        }
    }
}
