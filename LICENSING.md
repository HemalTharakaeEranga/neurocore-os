NeuroCore OS Multi-License Summary
==================================

NeuroCore OS is a Free and Open-Source AI/ML operating system repository that
combines components under several OSI-approved and open-content licenses.
Exact per-file license metadata follows the FSFE REUSE 3.3 specification and
is declared in REUSE.toml and individual SPDX file headers, with canonical
license texts located in LICENSES/.

- User-space Rust code (neuro, neurocore-daemon, neuro-bench), mkosi manifests,
  build/packaging/test scripts, and CI workflows:
  Dual-licensed under MIT OR Apache-2.0.
  See LICENSES/MIT.txt and LICENSES/Apache-2.0.txt.

- Linux kernel Kconfig fragments, kernel patches, and Rust-for-Linux kernel
  modules (kernel/configs/, kernel/patches/, kernel/rust-modules/):
  Licensed under GPL-2.0-only.
  See LICENSES/GPL-2.0-only.txt.

- Standalone Mojo 1.2.0 CPU/SIMD kernels and FFI bridges (mojo/):
  Licensed under Apache-2.0 WITH LLVM-exception.
  See LICENSES/Apache-2.0.txt and LICENSES/LLVM-exception.txt.

- Documentation and governance guides (*.md, docs/):
  Licensed under CC-BY-4.0.
  See LICENSES/CC-BY-4.0.txt.

- Brand artwork (penguin-and-gear logo and boot splash GIF):
  Copyright licensed under CC-BY-SA-4.0 (see LICENSES/CC-BY-SA-4.0.txt),
  subject to the separate trademark policy in TRADEMARKS.md.

- Third-party software included in built OS images:
  Retains its upstream licenses verbatim. Complete Corresponding Source (CCS)
  for GPL/LGPL components distributed in release images is packaged alongside
  each release via packaging/collect-gpl-sources.sh.
