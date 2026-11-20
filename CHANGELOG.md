<!--
SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
SPDX-License-Identifier: CC-BY-4.0
-->

# Changelog

All notable changes to NeuroCore OS are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-alpha] - 2026-11-21 ("Spark")

### Added
- **Declarative Debian 13.7 "Trixie" OS builder (`mkosi/`)** with explicit
  `core-libre` (strictly Debian `main`, zero `non-free-firmware`) and
  `baremetal-foss` (`main` + `non-free-firmware` + Mesa/Intel OpenCL) profiles.
- **Custom Linux 6.18 LTS kernel pipeline (`kernel/`)** with `CONFIG_RUST=y`,
  `CONFIG_SCHED_CLASS_EXT=y`, cross-vendor DRM/KFD drivers, Zstd SquashFS,
  CLUT224 boot logo injection, `neurocore_telemetry.ko` out-of-tree Rust kernel
  module, and `neurocore-next` Linux 7.3+ tracking fragment (`CONFIG_NOVA_CORE`).
- **Dual-Rust toolchain layout**: system Debian `rustc 1.85` reserved for
  reproducible kernel builds; pinned `Rust 1.100.0` workspace (`rust/`) for
  `neuro` CLI, `neurocore-daemon` (Unix sockets + `iceoryx2` tensor IPC), and
  `neuro-bench` (Burn, Polars, Linfa, Candle).
- **Standalone Mojo 1.2.0 CPU/SIMD kernels (`mojo/`)** using Mojo 1.2 syntax
  (`def`, `comptime`, `@export` C-ABI bridge) isolated from Modular MAX.
- **Integrated `pixi` + `uv` ML stack (`ml-stack/`)** covering PyTorch 2.15.0,
  Transformers, scikit-learn, MLflow 3.18.0, JupyterLab, `llama.cpp v1.0.0`
  dynamic backends over `/run/neurocore/llama.sock`, MIT-licensed Fashion-MNIST,
  and CC0-1.0 synthetic tabular benchmark data.
- **Dark-adapted 5-surface branding pipeline (`branding/`)** compiling the
  penguin-and-gear emblem and 30-frame animated GIF into `logo_linux_clut224.ppm`,
  GRUB2 theme (`#0b0f14` / `#22c55e`), Plymouth animated splash, FreeDesktop
  `hicolor` icons, and true-color TTY/MOTD banners.
- **Reproducible packaging & supply-chain assurance (`packaging/`, `tests/`,
  `.github/workflows/`)**: tri-mode hybrid BIOS/UEFI ISO, VirtualBox `.vdi`,
  QEMU `.qcow2`, GPLv2 Section 3 CCS archive, REUSE 3.3 lint, Syft SPDX/CycloneDX
  SBOMs with license policy gate, Grype CVE scan, and keyless Sigstore signing.
