// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

mod addon;
mod check;
mod new;
mod selftest;
mod train;

use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "neuro",
    version,
    about = "NeuroCore OS v0.1.0-alpha ('Spark') developer & AI runtime CLI"
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Inspect CPU x86-64-v3 SIMD flags, GPUs, Mesa/ROCm/Vulkan, sched_ext, and runtimes
    Check {
        /// Verify x86-64-v3 instruction set required by standalone Mojo 1.2.0 and exit non-zero if missing
        #[arg(long)]
        isa: bool,
        /// Run neuro-bench smoke tests after hardware inspection
        #[arg(long)]
        bench: bool,
        /// Emit machine-readable JSON diagnostics
        #[arg(long)]
        json: bool,
    },
    /// Scaffold a new NeuroCore project from /usr/share/neurocore/templates
    New {
        /// Template name: mojo-simd | rust-burn | rust-linfa-polars | python-pytorch
        template: String,
        /// Target directory name
        name: String,
    },
    /// Launch a training or benchmark script with NeuroCore hardware fallbacks and MLflow wiring
    Train {
        /// Path to script (.py, .mojo, or Cargo project directory)
        target: String,
        /// Scheduler profile via scxctl (auto | lowlatency | server | powersave | none)
        #[arg(long, default_value = "auto")]
        sched: String,
        /// Force CPU-only fallback mode
        #[arg(long)]
        cpu_only: bool,
        /// Extra arguments forwarded to the target command
        #[arg(last = true)]
        args: Vec<String>,
    },
    /// Manage quarantined opt-in non-OSI / proprietary addons (max, nvidia-cuda)
    Addon {
        #[command(subcommand)]
        action: addon::AddonCommand,
    },
    /// Run the NeuroCore OS v0.1.0-alpha end-to-end validation self-test suite
    Selftest {
        /// Skip checks requiring systemd services (useful in chroot/container CI)
        #[arg(long)]
        no_systemd: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Check { isa, bench, json } => check::run(isa, bench, json),
        Commands::New { template, name } => new::run(&template, &name),
        Commands::Train {
            target,
            sched,
            cpu_only,
            args,
        } => train::run(&target, &sched, cpu_only, &args),
        Commands::Addon { action } => addon::run(action),
        Commands::Selftest { no_systemd } => selftest::run(no_systemd),
    }
}
