// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

mod ipc_iox2;
mod ipc_unix;
mod telemetry;

use anyhow::Result;
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser)]
#[command(
    name = "neurocore-daemon",
    version,
    about = "NeuroCore OS system supervisor daemon (Unix socket control plane + iceoryx2 tensor IPC)"
)]
struct Args {
    /// Unix domain socket path for local control and status requests
    #[arg(long, default_value = "/run/neurocore/daemon.sock")]
    socket: PathBuf,

    /// Shared-memory metadata directory for Eclipse iceoryx2 tensor channels
    #[arg(long, default_value = "/run/neurocore/iceoryx2")]
    iox2_dir: PathBuf,

    /// Print a single telemetry snapshot as JSON and exit
    #[arg(long)]
    oneshot_status: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();

    if args.oneshot_status {
        let snap = telemetry::collect_snapshot();
        println!("{}", serde_json::to_string_pretty(&snap)?);
        return Ok(());
    }

    let iox2_channel = ipc_iox2::TensorChannelConfig::init(&args.iox2_dir)?;
    eprintln!(
        "neurocore-daemon: initialized iceoryx2 plane '{}' (backend={}, max_payload={} bytes)",
        iox2_channel.service_name, iox2_channel.backend, iox2_channel.max_tensor_bytes
    );

    ipc_unix::serve(&args.socket, &iox2_channel)
}
