# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Seeded into /home/neuro/workspace/README.txt from /etc/skel

NeuroCore OS v0.1.0-alpha ("Spark") Developer Workspace
=======================================================

Quick commands:
  neuro check --bench                   Inspect CPU SIMD, GPUs, sched_ext & run Rust ML smoke tests
  neuro new mojo-simd my-kernel         Create a standalone Mojo 1.2.0 CPU/SIMD project
  neuro new rust-burn my-cnn            Create a Rust Burn (CubeCL/Flex) deep learning project
  neuro new rust-linfa-polars my-tab    Create a pure-Rust Polars + Linfa tabular project
  neuro new python-pytorch my-exp       Create a PyTorch 2.15 + MLflow 3.18 experiment
  neuro addon list                      Inspect quarantined opt-in addons (MAX, NVIDIA CUDA)

Local Studio URLs (forward ports 5000 and 8888 in VirtualBox NAT settings):
  MLflow Tracking : http://127.0.0.1:5000
  JupyterLab      : http://127.0.0.1:8888
