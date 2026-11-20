#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Converts mkosi's .raw GPT disk image into a reproducible Zstd SquashFS +
# tri-mode hybrid BIOS/UEFI ISO, generating Syft SPDX & CycloneDX SBOMs before
# compression and validating GRUB's 462 MiB BIOS initrd ceiling + El Torito.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROFILE="${PROFILE:-baremetal-foss}"
VERSION="${VERSION:-$(cat "${REPO_ROOT}/VERSION")}"
ARCH="${ARCH:-amd64}"
OUT_DIR="${REPO_ROOT}/out"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${REPO_ROOT}" log -1 --pretty=%ct 2>/dev/null || date +%s)}"

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
if [[ ! -f "${RAW_IMG}" ]]; then
    RAW_IMG="${OUT_DIR}/neurocore-os_${VERSION}.raw"
fi
if [[ ! -f "${RAW_IMG}" ]]; then
    echo "ERROR: mkosi .raw image not found in ${OUT_DIR} (run 'make image PROFILE=${PROFILE}' first)." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/neurocore-iso.XXXXXX")"
MNT_ROOT="${WORK_DIR}/mnt-root"
ISO_STAGE="${WORK_DIR}/iso-staging"
LOOP_DEV=""

cleanup() {
    set +e
    mountpoint -q "${MNT_ROOT}" && sudo umount "${MNT_ROOT}"
    [[ -n "${LOOP_DEV}" ]] && sudo losetup -d "${LOOP_DEV}"
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

mkdir -p "${MNT_ROOT}" "${ISO_STAGE}/live" "${ISO_STAGE}/boot/grub"

echo "==> Attaching ${RAW_IMG} via loopback and locating GPT x86-64 root partition"
LOOP_DEV="$(sudo losetup --find --show --partscan "${RAW_IMG}")"
sudo partprobe "${LOOP_DEV}" || true

# Match GPT Linux x86-64 root type GUID (4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709)
ROOT_PART="$(lsblk -nrpo NAME,PARTTYPE "${LOOP_DEV}" \
    | awk 'tolower($2) == "4f68bce3-e8cd-4db1-96e7-fbcaf984b709" {print $1; exit}')"

if [[ -z "${ROOT_PART}" ]]; then
    # Fallback to last partition if mkosi used a generic Linux filesystem GUID
    ROOT_PART="$(lsblk -nrpo NAME,TYPE "${LOOP_DEV}" | awk '$2 == "part" {p=$1} END {print p}')"
fi
if [[ -z "${ROOT_PART}" ]]; then
    echo "ERROR: Could not find root partition inside ${RAW_IMG}" >&2
    exit 1
fi

echo "==> Mounting root partition ${ROOT_PART} -> ${MNT_ROOT}"
sudo mount -o ro "${ROOT_PART}" "${MNT_ROOT}"

# 1. Generate Dual-Format SBOMs (SPDX JSON + CycloneDX JSON) via Syft before SquashFS compression
SPDX_OUT="${OUT_DIR}/neurocore-${VERSION}-${PROFILE}.spdx.json"
CDX_OUT="${OUT_DIR}/neurocore-${VERSION}-${PROFILE}.cdx.json"
if command -v syft >/dev/null 2>&1; then
    echo "==> Generating Syft SPDX and CycloneDX SBOMs from staged rootfs"
    syft "dir:${MNT_ROOT}" \
        -o "spdx-json=${SPDX_OUT}" \
        -o "cyclonedx-json=${CDX_OUT}"
else
    echo "WARNING: 'syft' not installed; skipping SBOM generation." >&2
fi

# 2. Extract vmlinuz and initrd.img and enforce GRUB's 462 MiB BIOS ceiling
VMLINUZ="$(find "${MNT_ROOT}/boot" -maxdepth 1 -type f -name 'vmlinuz-*' | sort -V | tail -n 1)"
INITRD="$(find "${MNT_ROOT}/boot" -maxdepth 1 -type f -name 'initrd.img-*' | sort -V | tail -n 1)"
if [[ -z "${VMLINUZ}" || -z "${INITRD}" ]]; then
    echo "ERROR: vmlinuz-* or initrd.img-* missing under ${MNT_ROOT}/boot" >&2
    exit 1
fi

INITRD_BYTES="$(stat -c '%s' "${INITRD}")"
INITRD_MIB="$(( INITRD_BYTES / 1048576 ))"
echo "==> Kernel: $(basename "${VMLINUZ}"), Initrd: $(basename "${INITRD}") (${INITRD_MIB} MiB)"
if (( INITRD_MIB >= 400 )); then
    echo "ERROR: initrd (${INITRD_MIB} MiB) approaches GRUB Legacy BIOS 462 MiB ceiling!" >&2
    exit 1
fi

cp -f "${VMLINUZ}" "${ISO_STAGE}/live/vmlinuz"
cp -f "${INITRD}" "${ISO_STAGE}/live/initrd.img"
cp -f "${SCRIPT_DIR}/grub-iso.cfg" "${ISO_STAGE}/boot/grub/grub.cfg"
if [[ -d "${MNT_ROOT}/boot/grub/themes/neurocore" ]]; then
    mkdir -p "${ISO_STAGE}/boot/grub/themes"
    cp -a "${MNT_ROOT}/boot/grub/themes/neurocore" "${ISO_STAGE}/boot/grub/themes/"
fi

# 3. Deterministic Zstd SquashFS compression pinned to SOURCE_DATE_EPOCH
# Explicitly strip any static SSH host keys, histories, or transient tmp files.
echo "==> Compressing /live/filesystem.squashfs (Zstd level 19, SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH})"
sudo mksquashfs "${MNT_ROOT}" "${ISO_STAGE}/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level 19 -b 1M \
    -repro-time "${SOURCE_DATE_EPOCH}" \
    -noappend -no-progress \
    -wildcards \
    -e 'boot/vmlinuz-*' \
       'boot/initrd.img-*' \
       'etc/ssh/ssh_host_*' \
       'root/.bash_history' \
       'home/*/.bash_history' \
       'tmp/*' \
       'var/tmp/*'

# 4. Assemble reproducible tri-mode hybrid BIOS/UEFI ISO via grub-mkrescue
ISO_DATE="$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y%m%d%H%M%S00)"
ISO_OUT="${OUT_DIR}/neurocore-${VERSION}-${PROFILE}-${ARCH}.iso"
VOLID="NEUROCORE_010"

echo "==> Building tri-mode hybrid BIOS/UEFI ISO -> ${ISO_OUT}"
grub-mkrescue \
    -o "${ISO_OUT}" \
    "${ISO_STAGE}" \
    -- -volid "${VOLID}" \
    --modification-date="${ISO_DATE}"

# 5. Verify El Torito BIOS + UEFI boot records
echo "==> Verifying El Torito boot catalog via xorriso"
xorriso -indev "${ISO_OUT}" -report_el_torito plain

echo "==> Successfully built reproducible hybrid ISO: ${ISO_OUT}"
