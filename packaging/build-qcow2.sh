#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Converts mkosi's .raw image into a compressed QEMU/KVM .qcow2 disk image.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${PROFILE:-baremetal-foss}"
VERSION="${VERSION:-$(cat "${REPO_ROOT}/VERSION")}"
ARCH="${ARCH:-amd64}"
OUT_DIR="${REPO_ROOT}/out"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --arch)    ARCH="$2"; shift 2 ;;
        --out-dir) OUT_DIR="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

RAW_IMG="${OUT_DIR}/neurocore-os-${PROFILE}_${VERSION}.raw"
[[ -f "${RAW_IMG}" ]] || RAW_IMG="${OUT_DIR}/neurocore-os_${VERSION}.raw"
if [[ ! -f "${RAW_IMG}" ]]; then
    echo "ERROR: Raw disk image not found in ${OUT_DIR}" >&2
    exit 1
fi

QCOW2_OUT="${OUT_DIR}/neurocore-${VERSION}-${PROFILE}-${ARCH}.qcow2"
echo "==> Converting ${RAW_IMG} -> ${QCOW2_OUT} (compressed qcow2)"
qemu-img convert -f raw -O qcow2 -c "${RAW_IMG}" "${QCOW2_OUT}"
echo "==> QEMU disk image ready: ${QCOW2_OUT}"
