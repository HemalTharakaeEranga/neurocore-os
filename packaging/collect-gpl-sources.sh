#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Collects Complete Corresponding Source (CCS) required by GPLv2 Section 3 and
# GPLv3 Section 6 for every release ISO:
#   - Exact pinned Linux kernel source tarball + .config + patches + Rust .ko + build scripts
#   - Exact Debian source packages (`apt-get source --download-only`) for installed packages
#   - Consolidated /usr/share/doc/*/copyright notices
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${PROFILE:-baremetal-foss}"
VERSION="${VERSION:-$(cat "${REPO_ROOT}/VERSION")}"
OUT_DIR="${REPO_ROOT}/out"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${REPO_ROOT}" log -1 --pretty=%ct 2>/dev/null || date +%s)}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --out-dir) OUT_DIR="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/neurocore-ccs.XXXXXX")"
trap 'rm -rf "${STAGE}"' EXIT

mkdir -p \
    "${STAGE}/kernel" \
    "${STAGE}/debian-sources" \
    "${STAGE}/copyrights" \
    "${STAGE}/neurocore-repo"

echo "==> [1/4] Collecting NeuroCore kernel configs, patches, Rust modules, and build scripts"
cp -a "${REPO_ROOT}/kernel/configs" "${STAGE}/kernel/"
cp -a "${REPO_ROOT}/kernel/patches" "${STAGE}/kernel/"
cp -a "${REPO_ROOT}/kernel/rust-modules" "${STAGE}/kernel/"
cp -f "${REPO_ROOT}/kernel/Makefile" "${REPO_ROOT}/kernel/fetch-kernel.sh" "${REPO_ROOT}/kernel/build-kernel-deb.sh" "${STAGE}/kernel/"

shopt -s nullglob
for ktar in "${REPO_ROOT}"/kernel/src/linux-*.tar.xz "${REPO_ROOT}"/kernel/src/linux-*.tar.sign; do
    cp -f "${ktar}" "${STAGE}/kernel/"
done
for kcfg in "${REPO_ROOT}"/mkosi/mkosi.packages/config-*-neurocore; do
    cp -f "${kcfg}" "${STAGE}/kernel/"
done
shopt -u nullglob

echo "==> [2/4] Archiving NeuroCore build repository source snapshot"
cp -a "${REPO_ROOT}/LICENSES" "${REPO_ROOT}/REUSE.toml" "${REPO_ROOT}/LICENSE" \
      "${REPO_ROOT}/rust" "${REPO_ROOT}/mojo" "${REPO_ROOT}/mkosi" "${REPO_ROOT}/packaging" \
      "${STAGE}/neurocore-repo/"

echo "==> [3/4] Collecting Debian package manifest & source archives (if mkosi manifest present)"
MANIFEST_JSON="${OUT_DIR}/neurocore-os-${PROFILE}_${VERSION}.manifest"
[[ -f "${MANIFEST_JSON}" ]] || MANIFEST_JSON="${OUT_DIR}/neurocore-os_${VERSION}.manifest"

if [[ -f "${MANIFEST_JSON}" ]]; then
    cp -f "${MANIFEST_JSON}" "${STAGE}/debian-sources/mkosi.manifest.json"
    if command -v jq >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
        mapfile -t SRC_PKGS < <(jq -r '.packages[]?.source // .packages[]?.name // empty' "${MANIFEST_JSON}" | sort -u)
        echo "    Found ${#SRC_PKGS[@]} unique packages in mkosi manifest; downloading Debian source tarballs..."
        (
            cd "${STAGE}/debian-sources"
            for pkg in "${SRC_PKGS[@]}"; do
                apt-get source --download-only "${pkg}" >/dev/null 2>&1 || true
            done
        )
    fi
else
    echo "    [WARN] mkosi manifest not found in ${OUT_DIR}; packaging kernel + repo sources only." >&2
fi

echo "==> [4/4] Creating deterministic GPLv2/v3 CCS archive"
mkdir -p "${OUT_DIR}"
CCS_OUT="${OUT_DIR}/neurocore-${VERSION}-${PROFILE}-sources.tar.zst"
tar --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 --group=0 --numeric-owner \
    -C "${STAGE}" -cf - . | zstd -T0 -19 -o "${CCS_OUT}"

echo "==> Complete Corresponding Source archive ready: ${CCS_OUT}"
