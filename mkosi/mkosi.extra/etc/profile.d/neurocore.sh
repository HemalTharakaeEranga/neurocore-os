# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Exposes NeuroCore's isolated user-space ML Rust toolchain (1.100.0) and
# local MLflow endpoint without overriding Debian's /usr/bin/rustc (1.85)
# used by kernel build scripts.

if [ -d "/opt/ml/toolchains/rust/bin" ]; then
    export PATH="/opt/ml/toolchains/rust/bin:${PATH}"
fi

export MLFLOW_TRACKING_URI="${MLFLOW_TRACKING_URI:-http://127.0.0.1:5000}"
export NEUROCORE_VERSION="0.1.0-alpha"

# Auto-apply Intel i915 Vulkan serialization safeguard on Intel iGPUs
if [ -d "/sys/module/i915" ] && [ -z "${GGML_VK_SERIALIZE_SUBMISSIONS:-}" ]; then
    export GGML_VK_SERIALIZE_SUBMISSIONS=1
fi
