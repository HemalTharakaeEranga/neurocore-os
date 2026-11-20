<!--
SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
SPDX-License-Identifier: CC-BY-4.0
-->

# Contributing to NeuroCore OS

Thank you for helping build NeuroCore OS! We welcome issues, pull requests,
hardware test reports, kernel improvements, and documentation updates.

## Developer Certificate of Origin (DCO)

NeuroCore OS uses the **Developer Certificate of Origin (DCO 1.1)** rather than
a Contributor License Agreement (CLA). Every commit **must** include a
`Signed-off-by:` trailer confirming you have the legal right to submit your
work under the repository's applicable open-source license:

```bash
git commit -s -m "neuro-cli: add AVX2 check diagnostics"
```

By signing off, you certify the statements in <https://developercertificate.org/>.

## License Hygiene & REUSE 3.3 Rules

Every file added or modified must comply with **FSFE REUSE 3.3** (`reuse lint`):

- **Kernel code, configs, patches, and Rust `.ko` modules** (`kernel/configs/`,
  `kernel/patches/`, `kernel/rust-modules/`): **MUST** be `GPL-2.0-only`
  (never Apache-2.0 alone, which is incompatible with GPLv2).
- **User-space Rust, build/packaging/CI scripts**: `MIT OR Apache-2.0`.
- **Mojo 1.2.0 kernels (`mojo/`)**: `Apache-2.0 WITH LLVM-exception`.
  Must strictly target standalone Mojo 1.2.0 syntax (`def`, `comptime`, no
  legacy `fn`/`alias`/`@parameter`, and zero Modular MAX dependencies).
- **Documentation (`*.md`, `docs/`)**: `CC-BY-4.0`.
- **Brand artwork (`branding/source/`)**: `CC-BY-SA-4.0`.

## Pull Request Checklist

1. Commits are signed off with `git commit -s`.
2. `reuse lint` passes with zero warnings or missing license texts.
3. Shell scripts pass `shellcheck` and use LF line endings (`.gitattributes`).
4. Rust crates pass `cargo fmt --check`, `cargo clippy --workspace`, and `cargo test`.
5. No proprietary binaries, non-OSI dependencies, or LLM model weights are added
   to `core-libre` or `baremetal-foss` profiles.
