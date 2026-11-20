#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Fetches official canonical SPDX license texts into LICENSES/ for FSFE REUSE 3.3.
# Enforces HTTPS >= TLS 1.2 and atomic writes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LICENSES_DIR="${REPO_ROOT}/LICENSES"
mkdir -p "${LICENSES_DIR}"

SPDX_IDS=(
    "GPL-2.0-only"
    "Apache-2.0"
    "MIT"
    "BSD-3-Clause"
    "CC-BY-4.0"
    "CC-BY-SA-4.0"
    "CC0-1.0"
    "LLVM-exception"
)

if command -v reuse >/dev/null 2>&1; then
    echo "==> Fetching canonical SPDX texts using 'reuse download'..."
    (cd "${REPO_ROOT}" && reuse download "${SPDX_IDS[@]}")
    echo "==> Done. Verifying with 'reuse lint'..."
    (cd "${REPO_ROOT}" && reuse lint)
    exit 0
fi

echo "==> 'reuse' CLI not found; downloading canonical texts from spdx/license-list-data..."
BASE_URL="https://raw.githubusercontent.com/spdx/license-list-data/v3.26.0/text"
for id in "${SPDX_IDS[@]}"; do
    out="${LICENSES_DIR}/${id}.txt"
    if [[ -s "${out}" ]]; then
        echo "  [SKIP] ${id}.txt already exists"
        continue
    fi
    echo "  [GET]  ${id}.txt"
    curl --proto '=https' --tlsv1.2 -fsSL "${BASE_URL}/${id}.txt" -o "${out}.part"
    mv -f "${out}.part" "${out}"
done
echo "==> All canonical SPDX license texts downloaded to ${LICENSES_DIR}"
