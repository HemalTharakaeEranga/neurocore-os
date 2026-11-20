#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Stages cleanly licensed starter datasets into /usr/share/neurocore/datasets/:
#   1. Fashion-MNIST (zalandoresearch/fashion-mnist, MIT License) — verified
#      against official upstream checksums + IDX binary headers
#   2. Synthetic tabular benchmark dataset (generated deterministically, CC0-1.0)
#
# Classic MNIST is intentionally excluded due to unclear upstream licensing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-/usr/share/neurocore/datasets}"

FASHION_DIR="${TARGET_DIR}/fashion-mnist"
TABULAR_DIR="${TARGET_DIR}/synthetic-tabular"
mkdir -p "${FASHION_DIR}" "${TABULAR_DIR}"

BASE_URL="https://github.com/zalandoresearch/fashion-mnist/raw/master/data/fashion"

# Official zalandoresearch/fashion-mnist checksums (matching torchvision.datasets.FashionMNIST)
declare -A EXPECTED_MD5=(
    ["train-images-idx3-ubyte.gz"]="8d4fb7e6c68d591d4c3dfef9ec88bf0d"
    ["train-labels-idx1-ubyte.gz"]="25c81989df183df01b3e8a0aad5dffbe"
    ["t10k-images-idx3-ubyte.gz"]="bef4ecab320f06d8554ea6380940ec79"
    ["t10k-labels-idx1-ubyte.gz"]="bb300cfdad3c16e7a12a480ee83cd310"
)

echo "==> Fetching and verifying MIT-licensed Fashion-MNIST into ${FASHION_DIR}"
for f in "${!EXPECTED_MD5[@]}"; do
    dest="${FASHION_DIR}/${f}"
    if [[ ! -s "${dest}" ]]; then
        curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 2 \
            -o "${dest}.part" "${BASE_URL}/${f}"
        mv -f "${dest}.part" "${dest}"
    fi
    printf '%s  %s\n' "${EXPECTED_MD5[${f}]}" "${dest}" | md5sum -c -
done

if [[ ! -s "${FASHION_DIR}/LICENSE" ]]; then
    curl --proto '=https' --tlsv1.2 -fL --retry 3 \
        -o "${FASHION_DIR}/LICENSE.part" \
        "https://raw.githubusercontent.com/zalandoresearch/fashion-mnist/master/LICENSE"
    mv -f "${FASHION_DIR}/LICENSE.part" "${FASHION_DIR}/LICENSE"
fi

echo "==> Generating deterministic CC0-1.0 synthetic tabular dataset into ${TABULAR_DIR}"
python3 "${SCRIPT_DIR}/generate_synthetic_tabular.py" \
    --out-dir "${TABULAR_DIR}" --rows 5000 --seed 20260101

echo "==> Verified datasets ready in ${TARGET_DIR}"
