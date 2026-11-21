<!--
SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
SPDX-License-Identifier: CC-BY-4.0
-->

# NeuroCore OS v0.1.0-alpha ("Spark")

**NeuroCore OS** is a Free and Open-Source AI/ML operating system pairing **Debian 13.7 "Trixie"** (`glibc 2.41`) with a custom-compiled **Linux 6.18 LTS** kernel (`CONFIG_RUST=y`, `CONFIG_SCHED_CLASS_EXT=y`), declarative **mkosi** image generation, dual-toolchain Rust support, standalone Apache-2.0 **Mojo 1.2.0** CPU/SIMD kernels, cross-vendor open GPU compute (**Mesa Vulkan 1.4 / RADV / ANV / NVK / Rusticl**, **ROCm 10.x** open user space, **Intel NEO**), **Burn / Polars / Linfa / Candle**, **PyTorch 2.15.0 + MLflow 3.18.0**, **llama.cpp v1.0.0** over Unix domain sockets, and lock-free **Eclipse iceoryx2** zero-copy tensor IPC.

## Two-Tier FOSS Build Profiles

NeuroCore OS enforces strict license transparency across hardware boundaries:

| Profile | Debian Repos | Included Stack | Quarantined Add-Ons |
| --- | --- | --- | --- |
| `core-libre` | `main` only (zero `non-free-firmware`) | Standalone Apache-2.0 Mojo 1.2 CPU/SIMD, Burn, Polars, Linfa, Candle, PyTorch CPU, llama.cpp CPU/Vulkan (Lavapipe), MLflow, JupyterLab | Modular MAX, NVIDIA CUDA, vendor firmware blobs |
| `baremetal-foss` (default) | `main`, `non-free-firmware` | Everything in `core-libre` + redistributable GPU microcode blobs, Mesa RADV/ANV/NVK/Rusticl, open ROCm 10.x (excluding AMD `proprietary/`), MIT Intel Compute Runtime | Modular MAX (`neuro addon enable max`), NVIDIA CUDA (`neuro addon enable nvidia-cuda`) |

Neither profile pre-bundles Modular MAX (source-available MAX License), proprietary NVIDIA CUDA user-space libraries, or third-party LLM weights.

## Quickstart (Git, VirtualBox, USB & WSL2)

- **[docs/RUNBOOK.md](docs/RUNBOOK.md)** — Complete step-by-step operator & developer runbook: Git clone/pull/push/merge workflow, downloading or building `.iso`/`.vdi` images, VirtualBox 7.2 installation, bootable USB pen drive & laptop guide, and secure SSH tunneling.
- **[docs/BUILDING_WSL2.md](docs/BUILDING_WSL2.md)** — Local Windows + WSL2 build instructions.
- **[docs/SECURITY_ARCHITECTURE.md](docs/SECURITY_ARCHITECTURE.md)** — Defense-in-depth hardening audit & GitHub Actions verification workflow.

```bash
make doctor          # Verify host tools (Debian/Ubuntu or WSL2)
make branding        # Generate dark-adapted CLUT224, GRUB2, Plymouth, and hicolor icons
make rust-tools      # Compile neuro, neurocore-daemon, and neuro-bench (Rust 1.100)
make kernel          # Fetch, verify, patch, and build Linux 6.18 LTS + Rust .ko
make ml-stack        # Fetch MIT Fashion-MNIST and generate CC0 synthetic tabular data
make image           # Build declarative mkosi disk image (PROFILE=baremetal-foss or core-libre)
make iso vdi qcow2   # Package reproducible tri-mode BIOS/UEFI ISO, VirtualBox .vdi, QEMU .qcow2
make sbom            # Validate Syft SPDX/CycloneDX SBOM against profile license policy
make gpl-sources     # Collect GPLv2 Section 3 Complete Corresponding Source archive
make verify          # Run headless QEMU/KVM BIOS + UEFI smoke tests
```

## VirtualBox 7.2 Quickstart

1. Create a Linux (Debian 64-bit) VM with **4 vCPUs**, **8 GB RAM**, and **EFI enabled** (or Legacy BIOS).
2. Attach `out/neurocore-0.1.0-alpha-baremetal-foss-amd64.vdi` (persistent disk) or boot the hybrid `.iso`.
3. Configure **NAT Port Forwarding**:
   - Host `127.0.0.1:5000` -> Guest `5000` (**MLflow 3.18.0 UI**)
   - Host `127.0.0.1:8888` -> Guest `8888` (**JupyterLab**)
4. Inside the VM, run `neuro check --bench` or open `~/notebooks/00_quickstart.ipynb`.

## Repository Layout

- `kernel/` — Linux 6.18 LTS (+ `next` 7.3+) Kconfig fragments, patches, and `neurocore_telemetry` Rust kernel module (`GPL-2.0-only`).
- `rust/` — Cargo workspace (`Rust 1.100`) containing `neuro-cli`, `neurocore-daemon`, and `neuro-bench` (`MIT OR Apache-2.0`).
- `mojo/` — Standalone Mojo 1.2.0 CPU/SIMD kernels and C-ABI `iceoryx2` tensor bridge (`Apache-2.0 WITH LLVM-exception`).
- `ml-stack/` — `pixi` + `uv` manifests, `llama.cpp v1.0.0` dynamic-backend build script, MIT/CC0 dataset fetchers, self-tests, and quickstart notebook.
- `branding/` — Master penguin-and-gear artwork (`CC-BY-SA-4.0`) and 5-surface dark-mode asset compiler.
- `mkosi/` — Declarative Debian 13 "Trixie" image builder, profiles, chroot post-install, and FHS 3.0 `/etc`/`/usr` overlay.
- `packaging/` — Reproducible Zstd SquashFS + tri-mode BIOS/UEFI `grub-mkrescue` ISO, `.vdi`, `.qcow2`, and GPLv2 CCS packager.
- `tests/` & `.github/workflows/` — KVM BIOS/UEFI QEMU smoke tests, VirtualBox tests, SBOM license policy gate, REUSE 3.3 lint, Grype scan, and keyless Sigstore signing.

## Licensing & Governance

NeuroCore OS adheres to **FSFE REUSE 3.3** (`reuse lint`). See [LICENSE](LICENSE), [LICENSING.md](LICENSING.md), [REUSE.toml](REUSE.toml), [TRADEMARKS.md](TRADEMARKS.md), [CONTRIBUTING.md](CONTRIBUTING.md), [GOVERNANCE.md](GOVERNANCE.md), and [SECURITY.md](SECURITY.md).
