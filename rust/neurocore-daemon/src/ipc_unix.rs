// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use crate::ipc_iox2::TensorChannelConfig;
use crate::telemetry;
use anyhow::Result;
use serde::Serialize;
use std::path::Path;

const MAX_CMD_BYTES: u64 = 256;

#[derive(Serialize)]
struct DaemonResponse<'a> {
    service: &'a str,
    version: &'a str,
    ipc_tensor_plane: &'a TensorChannelConfig,
    telemetry: telemetry::TelemetrySnapshot,
}

#[cfg(unix)]
pub fn serve(socket_path: &Path, iox2_cfg: &TensorChannelConfig) -> Result<()> {
    use anyhow::Context;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::os::unix::net::UnixListener;

    if let Some(parent) = socket_path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create socket dir {}", parent.display()))?;
    }
    if socket_path.exists() {
        let meta = fs::symlink_metadata(socket_path)?;
        if meta.file_type().is_symlink() {
            anyhow::bail!(
                "Refusing to remove symlink at socket path {}",
                socket_path.display()
            );
        }
        let _ = fs::remove_file(socket_path);
    }

    let listener = UnixListener::bind(socket_path)
        .with_context(|| format!("Failed to bind AF_UNIX socket {}", socket_path.display()))?;
    // Strictly group-accessible (neurocore:neuro), never world-writable (0o660)
    fs::set_permissions(socket_path, fs::Permissions::from_mode(0o660))?;
    eprintln!(
        "neurocore-daemon: listening on unix://{} (mode=0660, max_cmd={}B)",
        socket_path.display(),
        MAX_CMD_BYTES
    );

    for stream in listener.incoming() {
        let Ok(mut stream) = stream else {
            continue;
        };
        let _ = handle_client(&mut stream, iox2_cfg);
    }

    Ok(())
}

#[cfg(unix)]
fn handle_client(
    stream: &mut std::os::unix::net::UnixStream,
    iox2_cfg: &TensorChannelConfig,
) -> Result<()> {
    use std::io::{BufRead, BufReader, Read, Write};
    use std::time::Duration;

    // Prevent slowloris / infinite-read DoS against the supervisor daemon
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;

    let mut line = String::new();
    let cloned = stream.try_clone()?;
    let mut reader = BufReader::new(cloned.take(MAX_CMD_BYTES));
    let _ = reader.read_line(&mut line);
    let cmd = line.trim();

    let payload = match cmd {
        "PING" | "HEALTH" => serde_json::json!({ "status": "ok", "pong": true }).to_string(),
        "STATUS" | "" => {
            let resp = DaemonResponse {
                service: "neurocore-daemon",
                version: env!("CARGO_PKG_VERSION"),
                ipc_tensor_plane: iox2_cfg,
                telemetry: telemetry::collect_snapshot(),
            };
            serde_json::to_string(&resp).unwrap_or_else(|_| "{\"status\":\"error\"}".into())
        }
        _ => serde_json::json!({
            "status": "error",
            "message": "Unknown command; allowed: PING, HEALTH, STATUS"
        })
        .to_string(),
    };

    stream.write_all(payload.as_bytes())?;
    stream.write_all(b"\n")?;
    Ok(())
}

#[cfg(not(unix))]
pub fn serve(socket_path: &Path, _iox2_cfg: &TensorChannelConfig) -> Result<()> {
    anyhow::bail!(
        "AF_UNIX socket server ({}) requires a Linux/Unix host.",
        socket_path.display()
    )
}
