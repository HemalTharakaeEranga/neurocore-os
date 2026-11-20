<!--
SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
SPDX-License-Identifier: CC-BY-4.0
-->

# NeuroCore OS Security Architecture, Audit Log & GitHub Actions Verification Workflow

NeuroCore OS v0.1.0-alpha ("Spark") enforces **defense-in-depth** across the
Linux 6.18 LTS kernel, host network/firewall, systemd ML services, user-space
Rust/Mojo/Python code, reproducible ISO packaging, and GitHub Actions CI/CD.

---

## 1. File-by-File Security & Bug Audit Findings (Fixed)

| # | Severity | Affected File(s) | Issue / Attack Surface Identified | Fix Applied |
| --- | --- | --- | --- | --- |
| 1 | **CRITICAL** | `mkosi/mkosi.postinst.chroot`, `etc/sudoers.d/` | Default `neuro:neurocore` credential + `NOPASSWD:ALL` + enabled `ssh.service` allowed LAN attackers root takeover. | Locked `root` (`passwd -l root`), removed `NOPASSWD:ALL`, added hardened `90-neurocore-hardened` (`use_pty`, `passwd_tries=3`, `timestamp_timeout=5`), forced first-login password rotation (`chage -d 0`), disabled `ssh.service` by default, and added loopback/key-only `10-neurocore-hardening.conf`. |
| 2 | **CRITICAL** | `mkosi/mkosi.postinst.chroot`, `packaging/wrap-iso.sh` | Static `/etc/ssh/ssh_host_*` keys inside a public Live ISO would expose the same private host key to every user (MITM). | Stripped static host keys in chroot and `mksquashfs -e 'etc/ssh/ssh_host_*'`; added `neurocore-ssh-keygen.service` to generate a unique Ed25519 key on first boot. |
| 3 | **CRITICAL** | `.github/workflows/ci-build-test.yml`, `release-iso.yml` | Piping remote `curl \| sudo sh` scripts (`syft`/`grype` installers) & mutable `@master` action tags exposed CI to supply-chain compromise. | Replaced with pinned release tarballs verified via official `sha256sum -c`, top-level `permissions: {}`, `persist-credentials: false`, job `timeout-minutes`, and `dtolnay/rust-toolchain@stable`. |
| 4 | **HIGH** | `mkosi/mkosi.extra/etc/systemd/system/neurocore-daemon.service` | Supervisor daemon lacked `User=`, running unnecessarily as `root`. | Created dedicated non-login `neurocore` system account (`User=neurocore`, `Group=neuro`), added `MemoryDenyWriteExecute=yes`, `RestrictAddressFamilies=AF_UNIX`, `IPAddressDeny=any`, zero capabilities, and AppArmor `enforce` profile. |
| 5 | **HIGH** | `mkosi/mkosi.extra/etc/systemd/system/neurocore-*.service` | MLflow, JupyterLab, and llama.cpp services lacked full kernel/network sandboxing (`IPAddressDeny`, seccomp filters, capability drop, `PrivateTmp`). | Added strict systemd sandboxing across all units: `IPAddressDeny=any` + `IPAddressAllow=localhost` for MLflow/Jupyter, `RestrictAddressFamilies=AF_UNIX` for `neurocore-daemon` & `llama.cpp`, `CapabilityBoundingSet=`, `SystemCallFilter=@system-service`, `ProtectKernel*`, `LockPersonality=yes`. |
| 6 | **HIGH** | `mkosi/mkosi.extra/etc/nftables.conf`, `etc/sysctl.d/`, `etc/modprobe.d/` | No host firewall, sysctl lockdown, or unused kernel protocol blacklist. | Added default-deny inbound/forward `nftables.conf`, KSPP `99-neurocore-hardening.conf` (`unprivileged_bpf_disabled=1`, `io_uring_disabled=2`, `kptr_restrict=2`, `yama.ptrace_scope=2`), and `99-neurocore-blacklist.conf`. |
| 7 | **HIGH** | `kernel/configs/neurocore_x86_64.fragment`, `kernel/fetch-kernel.sh` | Missing KSPP compile-time flags (`LANDLOCK`, `APPARMOR`, `LOCKDOWN`, `BPF_UNPRIV_DEFAULT_OFF`, `LEGACY_TIOCSTI=n`); dynamic GPG key fetch without pinned fingerprints. | Enabled full KSPP flags (asserted in `build-kernel-deb.sh` + boot cmdline `lsm=landlock,lockdown,yama,apparmor,bpf lockdown=integrity`) and pinned Torvalds/GregKH 40-char GPG primary fingerprints with `VALIDSIG` verification. |
| 8 | **HIGH** | `rust/neuro-cli/src/{check.rs,new.rs,train.rs,addon.rs}` | `sh -c format!(...)` shell invocation in `check.rs`; missing path-traversal/symlink checks in `new.rs` & `addon.rs`; flag-injection (`-c`) risk in `train.rs`. | Replaced `sh -c` with pure-Rust `PATH` lookup; added `validate_project_name()` + `symlink_metadata()` guards; added leading-`-` rejection + `fs::canonicalize` + `--` separator in `train.rs`. |
| 9 | **HIGH** | `rust/neurocore-daemon/src/ipc_unix.rs` | Unbounded `read_line()` with no socket timeout allowed local single-threaded DoS hanging the supervisor daemon. | Added 2-second read/write timeouts, 256-byte `Read::take(MAX_CMD_BYTES)` cap, symlink guard, `0660` permissions, and strict command allowlist (`PING`, `HEALTH`, `STATUS`). |
| 10 | **HIGH** | `mojo/kernels/tensor_bridge.mojo` | Unbounded `m * n`, `m * k`, `k * n` C-ABI FFI dimensions risked integer overflow and out-of-bounds memory corruption. | Added `MAX_MATMUL_DIM` (16,384) and `MAX_TENSOR_ELEMS` (268M elements) bounds checks returning error codes `-1`/`-2` before pointer arithmetic. |
| 11 | **MEDIUM** | `kernel/patches/*.patch` | Kernel patches lacked automated hunk-integrity verification before CI builds. | Added automated unified diff hunk-count validation in `tests/verify-security-hardening.py` to fail fast on malformed patches. |
| 12 | **MEDIUM** | `ml-stack/llama-cpp-build.sh`, `ml-stack/fetch-datasets.sh`, `ml-stack/neuro_selftest/pytorch_mlflow.py` | Predictable `/tmp/neurocore-llama-build` directory (CWE-377 race); unverified Fashion-MNIST downloads; unconstrained `MLFLOW_TRACKING_URI`. | Switched to private `mktemp -d` (`chmod 0700`); enforced official Fashion-MNIST checksum verification + TLS 1.2+; enforced loopback-only MLflow URI check by default. |
| 13 | **MEDIUM** | `.github/workflows/ci-build-test.yml`, `branding/motd/10-neurocore`, `tests/vbox-smoke.sh` | World-writable `chmod 0666 /dev/kvm`; ShellCheck SC2012/SC2059 warnings in MOTD; unnecessary default SSH NAT forward in VirtualBox smoke test. | Switched KVM to `0660` + `kvm` group (`sg kvm`); refactored MOTD with safe globs & `%s`/`%b` format strings; gated VirtualBox SSH forwarding behind explicit `--enable-ssh`. |

---

## 2. Layered OS Security Architecture

1. **Kernel Self-Protection (Ring 0)**: Linux 6.18 LTS compiled with `LLVM=1`, `CONFIG_LSM="landlock,lockdown,yama,apparmor,bpf"`, `lockdown=integrity`, `CONFIG_BPF_UNPRIV_DEFAULT_OFF=y`, `CONFIG_HARDENED_USERCOPY=y`, `CONFIG_FORTIFY_SOURCE=y`, `CONFIG_STACKPROTECTOR_STRONG=y`, `CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y`, `CONFIG_INIT_ON_FREE_DEFAULT_ON=y`, `CONFIG_SLAB_FREELIST_HARDENED=y`, `CONFIG_LEGACY_TIOCSTI=n`, `CONFIG_DEVMEM=n`.
2. **Network & Host Perimeter**: Default-deny inbound/forward `nftables` (`etc/nftables.conf`); zero open LAN ports; `ssh.service` disabled by default (key-only + loopback-only if enabled); MLflow and JupyterLab restricted to `127.0.0.1` + eBPF `IPAddressDeny=any` / `IPAddressAllow=localhost`.
3. **Process & IPC Confinement**: Non-root `neurocore` daemon account confined by AppArmor (`enforce` mode) and systemd seccomp/capability/namespace restrictions; `llama.cpp` and `neurocore-daemon` restricted to `AF_UNIX` sockets only (zero TCP/UDP socket syscalls allowed).
4. **Supply Chain & License Integrity**: Pinned GPG kernel verification, verified dataset checksums, FSFE REUSE 3.3, Syft SPDX + CycloneDX SBOMs, license quarantine gate (`verify-sbom-licenses.py`), Grype critical-CVE gate, keyless Sigstore `cosign`, and SLSA v1 provenance.

---

## 3. Continuous Verification Workflow (Local + GitHub Actions)

### Step A — Run Local Security Gate Before Pushing
```bash
python3 tests/verify-security-hardening.py
python3 tests/verify-sbom-licenses.py --self-test
make security-audit
```

### Step B — Push to GitHub & Inspect Automated Security Checks
Pushing to GitHub automatically triggers four workflows under `.github/workflows/`:

1. **[security-audit.yml](.github/workflows/security-audit.yml)** *(runs on every push, PR, manual trigger, and weekly Monday 03:00 UTC)*:
   - **Gitleaks** secret & credential leak scan (`.gitleaks.toml`)
   - **NeuroCore OS Hardening & Bug Policy Gate** (`tests/verify-security-hardening.py`)
   - **ShellCheck (`-S info`)**, **Bandit (Python SAST)**, **Ruff security rules (`S,B,E,F`)**
   - **actionlint** + **zizmor** (GitHub Actions security audit)
   - **Rust Clippy (`-D warnings`)**, unit tests & **cargo-deny** (RustSec CVEs + license allowlist via `rust/deny.toml`)
   - **CodeQL SAST** (`python` & `actions` with `security-extended` queries)
   - **PR Dependency Review** (blocks High/Critical CVEs and proprietary licenses on PRs)
2. **[reuse-and-sbom.yml](.github/workflows/reuse-and-sbom.yml)** — FSFE REUSE 3.3 compliance, manifest parsing, and SBOM policy tests.
3. **[ci-build-test.yml](.github/workflows/ci-build-test.yml)** — Full branding, Rust, mkosi, ISO, SBOM, and headless KVM BIOS + UEFI boot tests.
4. **[release-iso.yml](.github/workflows/release-iso.yml)** — Dual-profile (`core-libre` & `baremetal-foss`) ISO/VDI/QCOW2 builds, GPLv2 CCS archive, Grype `--fail-on critical`, Sigstore keyless signing, and SLSA v1 provenance.

### Step C — Recommended GitHub Repository Security Settings
Once pushed to GitHub, enable in **Repository -> Settings -> Code security & Branches**:
1. **Branch protection on `main`**: Require pull requests + require status checks (`Security Audit & Hardening Gate`, `REUSE 3.3, Static Lint & SBOM Policy`, `CI Build & Dual-Firmware KVM Boot Test`) before merging.
2. **Code security**: Enable **Dependabot alerts**, **Dependabot security updates**, **Secret scanning**, and **Push protection**.
3. **Actions**: Under *Settings -> Actions -> General*, set **Workflow permissions** to *Read repository contents and packages permissions* (matches our least-privilege `permissions: {}`).
