<!--
SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
SPDX-License-Identifier: CC-BY-4.0
-->

# Building NeuroCore OS on Windows + WSL2 & GitHub Actions

Because Linux kernel compilation (`make LLVM=1`), `mkosi`, `mksquashfs`, and
`grub-mkrescue` require a Linux kernel and POSIX filesystem semantics, Windows
developers build locally inside **WSL2 (Debian 13 or Ubuntu 24.04/26.04)** and
verify end-to-end builds automatically in **GitHub Actions CI**.

## 1. Clone on Native WSL2 ext4 Filesystem (Important for Speed & Permissions)

Avoid building kernel/mkosi trees directly under `/mnt/d/` (9pdrvfs is slow for
hundreds of thousands of kernel/rootfs files and drops Linux execute/inode
semantics). Instead, sync or clone into your WSL2 home directory:

```bash
# Inside WSL2:
mkdir -p ~/src
rsync -av --exclude out --exclude rust/target "/mnt/d/NeuroCore OS/" ~/src/neurocore-os/
cd ~/src/neurocore-os
```

When you finish an image build, copy release outputs back to Windows for VirtualBox:

```bash
mkdir -p "/mnt/d/NeuroCore OS/out"
cp -v out/neurocore-0.1.0-alpha-* "/mnt/d/NeuroCore OS/out/"
```

## 2. Install Host Prerequisites in WSL2 (Debian 13 / Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y \
  git make bc bison flex dwarves libssl-dev libelf-dev cpio kmod \
  gcc g++ clang-19 lld-19 llvm-19 bindgen rustc rust-src \
  mkosi squashfs-tools grub-pc-bin grub-efi-amd64-bin grub-common \
  xorriso mtools dosfstools parted qemu-utils qemu-system-x86 ovmf \
  imagemagick python3 python3-pil python3-venv curl zstd gpgv jq \
  debhelper dpkg-dev rsync shellcheck
```

Install the user-space ML Rust toolchain (`1.100.0`) via `rustup` (kept separate
from Debian's `/usr/bin/rustc` used for kernel builds) and `reuse` + `syft`:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.100.0
pipx install reuse
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sudo sh -s -- -b /usr/local/bin
```

Run `make doctor` to verify all host prerequisites.

## 3. Build Workflow in WSL2

```bash
# 1. Generate dark-adapted kernel PPM, GRUB2 theme, Plymouth frames, and hicolor icons
make branding

# 2. Build user-space Rust tools (neuro, neurocore-daemon, neuro-bench)
make rust-tools

# 3. Fetch, verify, patch, and compile Linux 6.18 LTS + neurocore_telemetry.ko
make kernel

# 4. Stage Fashion-MNIST (MIT) and synthetic tabular dataset (CC0-1.0)
make ml-stack

# 5. Build declarative mkosi image (baremetal-foss or core-libre)
make image PROFILE=baremetal-foss

# 6. Package hybrid BIOS/UEFI ISO, VirtualBox VDI, QEMU QCOW2, SBOM, and GPLv2 CCS
make iso vdi qcow2 sbom gpl-sources
```

## 4. Test in VirtualBox 7.2 on Windows

From PowerShell (or Git Bash / WSL2 with `VBoxManage.exe` on PATH):

```powershell
# Or use the automated script: bash tests/vbox-smoke.sh
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" --version
```

Configure the VM with:
- **CPU**: 4 vCPU (VirtualBox 7.2 passes through AVX2/x86-64-v3 cleanly)
- **Memory**: 8192 MB
- **Firmware**: EFI or BIOS (both tested by tri-mode hybrid ISO)
- **Network**: NAT with port forwarding:
  - `5000 -> 5000` (MLflow: `http://127.0.0.1:5000`)
  - `8888 -> 8888` (JupyterLab: `http://127.0.0.1:8888`)

## 5. GitHub Actions CI

Pushing to GitHub automatically runs:
- `.github/workflows/reuse-and-sbom.yml` on every PR/push (`reuse lint`, static lints, SBOM policy tests)
- `.github/workflows/ci-build-test.yml` (builds branding, Rust, kernel, mkosi image, hybrid ISO, and boots both BIOS + UEFI under `/dev/kvm`)
- `.github/workflows/release-iso.yml` on `v*` tags (builds `core-libre` + `baremetal-foss`, GPLv2 CCS archive, Syft/Grype audit, keyless Sigstore `cosign` signatures, and SLSA v1 provenance)
