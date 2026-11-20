// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use anyhow::{Result, bail};
use clap::Subcommand;
use std::fs;
use std::io::{self, Write};
use std::path::Path;

const ADDONS_DIR: &str = "/opt/ml/addons";

#[derive(Subcommand)]
pub enum AddonCommand {
    /// List optional non-OSI / proprietary addons and their quarantine status
    List,
    /// Enable an opt-in addon after reviewing and accepting its upstream license terms
    Enable {
        /// Addon identifier: max | nvidia-cuda
        name: String,
        /// Explicitly acknowledge reading the upstream non-OSI license URL
        #[arg(long)]
        accept_upstream_license: bool,
    },
    /// Show installation status for opt-in addons
    Status,
}

struct AddonSpec {
    id: &'static str,
    title: &'static str,
    license_name: &'static str,
    license_url: &'static str,
    notes: &'static str,
}

const ADDONS: &[AddonSpec] = &[
    AddonSpec {
        id: "max",
        title: "Modular MAX GPU Runtime & Graph Compiler",
        license_name: "Modular MAX License (Source-Available / Non-OSI)",
        license_url: "https://www.modular.com/legal/max-mojo-license",
        notes: "Required only for Mojo GPU programming. Standalone Mojo 1.2.0 CPU/SIMD is already pure Apache-2.0 WITH LLVM-exception.",
    },
    AddonSpec {
        id: "nvidia-cuda",
        title: "NVIDIA Proprietary CUDA User-Space Stack (libcuda, cuDNN, NCCL)",
        license_name: "NVIDIA CUDA Toolkit EULA (Proprietary)",
        license_url: "https://docs.nvidia.com/cuda/eula/index.html",
        notes: "Pure-FOSS NVIDIA compute is available without this addon via mainline nouveau/Nova + Mesa NVK Vulkan 1.4.",
    },
];

pub fn run(action: AddonCommand) -> Result<()> {
    match action {
        AddonCommand::List | AddonCommand::Status => {
            println!("NeuroCore OS Quarantined Opt-In Addons (NEVER bundled in core ISOs):");
            for a in ADDONS {
                let installed = Path::new(ADDONS_DIR).join(a.id).join(".enabled").exists();
                println!(
                    "\n  [{}] {} ({})\n      License : {}\n      Terms   : {}\n      Notes   : {}",
                    if installed { "ENABLED" } else { "DISABLED" },
                    a.id,
                    a.title,
                    a.license_name,
                    a.license_url,
                    a.notes
                );
            }
            Ok(())
        }
        AddonCommand::Enable {
            name,
            accept_upstream_license,
        } => enable_addon(&name, accept_upstream_license),
    }
}

fn enable_addon(name: &str, accepted_flag: bool) -> Result<()> {
    let Some(spec) = ADDONS.iter().find(|a| a.id == name) else {
        bail!("Unknown addon '{}'. Valid addons: max, nvidia-cuda", name);
    };

    println!("==================================================================");
    println!("OPT-IN NON-OSI ADDON LICENSE NOTICE: {}", spec.title);
    println!("==================================================================");
    println!("License : {}", spec.license_name);
    println!("Terms   : {}", spec.license_url);
    println!("Details : {}", spec.notes);
    println!("Install : {}/{}", ADDONS_DIR, spec.id);
    println!("==================================================================");

    if !accepted_flag {
        print!("Have you reviewed and accepted the upstream license terms? [yes/NO]: ");
        io::stdout().flush()?;
        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        if input.trim().to_lowercase() != "yes" {
            bail!("Addon installation aborted. Core NeuroCore OS remains 100% FOSS.");
        }
    }

    let addon_dir = Path::new(ADDONS_DIR).join(spec.id);
    if addon_dir.exists() && fs::symlink_metadata(&addon_dir)?.file_type().is_symlink() {
        bail!("Refusing to use symlinked addon directory {}", addon_dir.display());
    }
    fs::create_dir_all(&addon_dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&addon_dir, fs::Permissions::from_mode(0o750))?;
    }
    fs::write(
        addon_dir.join(".enabled"),
        format!("addon={}\nlicense={}\n", spec.id, spec.license_name),
    )?;

    println!(
        "\nQuarantine directory initialized at {}.",
        addon_dir.display()
    );
    match spec.id {
        "max" => println!(
            "Next step: run `pixi init {0} && pixi add --manifest-path {0}/pixi.toml max` \
             to install MAX strictly inside {0} without modifying /opt/ml/envs/mojo.",
            addon_dir.display()
        ),
        "nvidia-cuda" => println!(
            "Next step: enable Debian 'non-free' in a dedicated APT source or install \
             NVIDIA user-space CUDA wheels strictly inside {0}.",
            addon_dir.display()
        ),
        _ => {}
    }

    Ok(())
}
