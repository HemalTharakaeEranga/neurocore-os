#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Scripted VirtualBox 7.2 validation test (4 vCPU, 8 GB RAM, EFI/BIOS,
# NAT port forwards 5000 -> MLflow and 8888 -> JupyterLab).
set -euo pipefail

ISO_PATH=""
VDI_PATH=""
VM_NAME="NeuroCore-OS-Smoke-010"
FIRMWARE="efi"
ENABLE_SSH="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)        ISO_PATH="$2"; shift 2 ;;
        --vdi)        VDI_PATH="$2"; shift 2 ;;
        --name)       VM_NAME="$2"; shift 2 ;;
        --firmware)   FIRMWARE="$2"; shift 2 ;;
        --enable-ssh) ENABLE_SSH="true"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

VBOX_BIN="$(command -v VBoxManage || command -v VBoxManage.exe || true)"
if [[ -z "${VBOX_BIN}" ]]; then
    echo "ERROR: VBoxManage / VBoxManage.exe not found on PATH." >&2
    exit 1
fi

echo "==> VirtualBox version: $("${VBOX_BIN}" --version)"

cleanup() {
    set +e
    "${VBOX_BIN}" controlvm "${VM_NAME}" poweroff >/dev/null 2>&1 || true
    sleep 2
    "${VBOX_BIN}" unregistervm "${VM_NAME}" --delete >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Creating VirtualBox VM '${VM_NAME}' (4 vCPU, 8192 MiB RAM, firmware=${FIRMWARE})"
"${VBOX_BIN}" createvm --name "${VM_NAME}" --ostype Debian_64 --register
"${VBOX_BIN}" modifyvm "${VM_NAME}" \
    --cpus 4 \
    --memory 8192 \
    --vram 128 \
    --graphicscontroller vmsvga \
    --firmware "${FIRMWARE}" \
    --nic1 nat \
    --natpf1 "mlflow,tcp,127.0.0.1,5000,,5000" \
    --natpf1 "jupyter,tcp,127.0.0.1,8888,,8888"

if [[ "${ENABLE_SSH}" == "true" ]]; then
    "${VBOX_BIN}" modifyvm "${VM_NAME}" --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
fi

"${VBOX_BIN}" storagectl "${VM_NAME}" --name "SATA" --add sata --controller IntelAhci

if [[ -n "${VDI_PATH}" && -f "${VDI_PATH}" ]]; then
    "${VBOX_BIN}" storageattach "${VM_NAME}" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "${VDI_PATH}"
fi
if [[ -n "${ISO_PATH}" && -f "${ISO_PATH}" ]]; then
    "${VBOX_BIN}" storageattach "${VM_NAME}" --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium "${ISO_PATH}"
fi

echo "==> Starting VM headless for 45s smoke verification..."
"${VBOX_BIN}" startvm "${VM_NAME}" --type headless
sleep 45

STATE="$("${VBOX_BIN}" showvminfo "${VM_NAME}" --machinereadable | awk -F= '/^VMState=/{gsub(/"/,"",$2); print $2}')"
echo "==> VM state after 45s: ${STATE}"
if [[ "${STATE}" != "running" ]]; then
    echo "ERROR: VirtualBox VM failed to remain running (state=${STATE})" >&2
    exit 1
fi

echo "[PASS] VirtualBox 7.2 smoke test passed (VM running; MLflow :5000 & Jupyter :8888 forwarded)."
