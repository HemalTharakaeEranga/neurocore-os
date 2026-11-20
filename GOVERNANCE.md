<!--
SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
SPDX-License-Identifier: CC-BY-4.0
-->

# NeuroCore OS Governance

## Phase 1: Founder-Maintainer Stewardship (`v0.1.0-alpha` – `v0.3.0-rc`)

During the initial alpha, beta, and release-candidate milestones, NeuroCore OS
operates under transparent founder-maintainer stewardship focused on rapid
architectural execution while preserving strict FOSS licensing hygiene:

- All architecture decisions, kernel bumps, and build profile changes are
  proposed via public GitHub Pull Requests or RFC issues.
- No proprietary software or non-OSI licenses may enter `core-libre` or
  `baremetal-foss` base images.
- Release tags require all CI quality gates (QEMU KVM boot, REUSE 3.3 lint,
  SBOM license verification, Grype critical-CVE gate, and GPLv2 CCS packaging).

## Phase 2: Multi-Maintainer Core Council (`v1.0.0` "Core" and Beyond)

Prior to tagging `v1.0.0`, governance transitions to a **Core Maintainer Council**
of 3 to 5 active contributors representing distinct subsystems:

1. **Kernel & Scheduling** (`kernel/`, `sched_ext`, Rust-for-Linux modules)
2. **OS Image & Packaging** (`mkosi/`, `packaging/`, reproducible builds, SBOM/CCS)
3. **ML Runtime & Tooling** (`rust/`, `mojo/`, `ml-stack/`, GPU driver stack)
4. **Release Engineering & Security** (`.github/workflows/`, Sigstore, CVE triage)

### Decision-Making

- **Lazy consensus** for routine fixes and maintenance PRs (one maintainer
  approval + green CI).
- **Majority council vote** (minimum 7-day public RFC comment period) for
  breaking CLI contracts, kernel LTS transitions, licensing policy updates, or
  adding/removing council members.
- **No single-vendor veto**: no single corporate employer may hold a majority
  of council seats once Phase 2 is active.
