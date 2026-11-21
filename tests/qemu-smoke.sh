#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Automated headless QEMU/KVM dual-firmware (SeaBIOS + UEFI OVMF) smoke test.
# Enforces a fail-fast /dev/kvm gate so CI never silently degrades to slow TCG.
set -euo pipefail

ISO_PATH=""
TIMEOUT_SEC="${QEMU_TIMEOUT:-90}"
QEMU_MEM="${QEMU_MEM:-4G}"
LOG_DIR="tests/logs"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)     ISO_PATH="$2"; shift 2 ;;
        --timeout) TIMEOUT_SEC="$2"; shift 2 ;;
        --log-dir) LOG_DIR="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "${ISO_PATH}" || ! -f "${ISO_PATH}" ]]; then
    echo "ERROR: ISO image not found: ${ISO_PATH}" >&2
    exit 1
fi

# Fail-fast KVM hardware virtualization gate (Section 5.3)
if [[ ! -w /dev/kvm ]]; then
    echo "ERROR: /dev/kvm is not writable. Refusing to silently fall back to software TCG emulation." >&2
    exit 1
fi

mkdir -p "${LOG_DIR}"

OVMF_CODE=""
OVMF_VARS=""
for cand in \
    /usr/share/OVMF/OVMF_CODE_4M.fd \
    /usr/share/OVMF/OVMF_CODE.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.fd; do
    if [[ -f "${cand}" ]]; then
        OVMF_CODE="${cand}"
        break
    fi
done
for cand in \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/OVMF/OVMF_VARS.fd \
    /usr/share/edk2/ovmf/OVMF_VARS.fd; do
    if [[ -f "${cand}" ]]; then
        OVMF_VARS="${cand}"
        break
    fi
done

run_boot_mode() {
    local mode="$1"
    local log_file="${LOG_DIR}/qemu-${mode}.log"
    local tmp_vars=""
    rm -f "${log_file}"

    local qemu_args=(
        -enable-kvm
        -cpu host
        -m "${QEMU_MEM}"
        -smp 4
        -display none
        -no-reboot
        -cdrom "${ISO_PATH}"
        -boot d
        -serial "file:${log_file}"
        -monitor none
    )

    if [[ "${mode}" == "uefi" ]]; then
        if [[ -z "${OVMF_CODE}" ]]; then
            echo "ERROR: OVMF_CODE.fd not found; install 'ovmf' package." >&2
            exit 1
        fi
        qemu_args+=(-machine q35 -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}")
        if [[ -n "${OVMF_VARS}" ]]; then
            tmp_vars="$(mktemp "${TMPDIR:-/tmp}/ovmf-vars.XXXXXX.fd")"
            cp -f "${OVMF_VARS}" "${tmp_vars}"
            qemu_args+=(-drive "if=pflash,format=raw,file=${tmp_vars}")
        fi
    fi

    echo "==> Booting ${ISO_PATH} in QEMU/KVM (${mode^^} mode, mem=${QEMU_MEM}, timeout=${TIMEOUT_SEC}s)"
    qemu-system-x86_64 "${qemu_args[@]}" >/dev/null 2>&1 &
    local qpid=$!

    local elapsed=0
    local booted=0
    while (( elapsed < TIMEOUT_SEC )); do
        if [[ -s "${log_file}" ]] && grep -qE "NeuroCore OS|neurocore login:|Reached target.*multi-user" "${log_file}"; then
            booted=1
            break
        fi
        if ! kill -0 "${qpid}" 2>/dev/null; then
            break
        fi
        sleep 2
        elapsed=$(( elapsed + 2 ))
    done

    kill "${qpid}" 2>/dev/null || true
    wait "${qpid}" 2>/dev/null || true
    [[ -n "${tmp_vars}" ]] && rm -f "${tmp_vars}"

    if (( booted == 1 )); then
        echo "[PASS] ${mode^^} boot reached NeuroCore OS console in ${elapsed}s (see ${log_file})"
    else
        echo "ERROR: ${mode^^} boot did not reach multi-user/login within ${TIMEOUT_SEC}s." >&2
        if [[ -s "${log_file}" ]]; then
            tail -n 60 "${log_file}" >&2 || true
        else
            echo "       (serial log ${log_file} was empty)" >&2
        fi
        exit 1
    fi
}

run_boot_mode "bios"
run_boot_mode "uefi"
echo "==> Dual-firmware BIOS + UEFI QEMU/KVM boot verification PASSED."
