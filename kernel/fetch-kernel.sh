#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Downloads and cryptographically verifies a pinned Linux kernel source tarball
# from cdn.kernel.org against pinned Linus Torvalds & Greg Kroah-Hartman GPG
# primary key fingerprints (prevents WKD/keyserver substitution attacks).
set -euo pipefail

VERSION="6.18.64"
DEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/src"
SKIP_VERIFY="false"

# Official kernel.org release signing primary fingerprints
readonly FINGERPRINT_TORVALDS="ABAF11C65A2970B130ABE3C479BE3E4300411886"
readonly FINGERPRINT_GREGKH="647F28654894E3BD457199BE38DBBDC86092693E"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="$2"; shift 2 ;;
        --dest)        DEST_DIR="$2"; shift 2 ;;
        --skip-verify) SKIP_VERIFY="true"; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Validate version string strictly against path/URL injection
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "ERROR: Invalid kernel version format: '${VERSION}'" >&2
    exit 2
fi

if [[ "${SKIP_VERIFY}" == "true" && "${CI:-}" == "true" ]]; then
    echo "ERROR: --skip-verify is strictly prohibited in CI builds." >&2
    exit 1
fi

MAJOR="${VERSION%%.*}"
SERIES="v${MAJOR}.x"
TAR_XZ="linux-${VERSION}.tar.xz"
TAR_SIGN="linux-${VERSION}.tar.sign"
BASE_URL="https://cdn.kernel.org/pub/linux/kernel/${SERIES}"

mkdir -p "${DEST_DIR}"
EXTRACT_DIR="${DEST_DIR}/linux-${VERSION}"

if [[ -d "${EXTRACT_DIR}" && -f "${EXTRACT_DIR}/Makefile" ]]; then
    echo "==> Kernel source already extracted at ${EXTRACT_DIR}"
    exit 0
fi

cd "${DEST_DIR}"

if [[ ! -f "${TAR_XZ}" ]]; then
    echo "==> Downloading ${BASE_URL}/${TAR_XZ}"
    curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 3 -o "${TAR_XZ}.part" "${BASE_URL}/${TAR_XZ}"
    mv -f "${TAR_XZ}.part" "${TAR_XZ}"
fi

if [[ ! -f "${TAR_SIGN}" ]]; then
    echo "==> Downloading ${BASE_URL}/${TAR_SIGN}"
    curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 3 -o "${TAR_SIGN}.part" "${BASE_URL}/${TAR_SIGN}"
    mv -f "${TAR_SIGN}.part" "${TAR_SIGN}"
fi

if [[ "${SKIP_VERIFY}" != "true" ]]; then
    if ! command -v gpg >/dev/null 2>&1; then
        echo "ERROR: 'gpg' is required to verify ${TAR_SIGN}." >&2
        exit 1
    fi

    GNUPGHOME="$(mktemp -d)"
    export GNUPGHOME
    chmod 0700 "${GNUPGHOME}"
    trap 'rm -rf "${GNUPGHOME}"' EXIT

    echo "==> Importing pinned kernel.org release keys into isolated keyring"
    gpg --batch --keyserver hkps://keyserver.ubuntu.com \
        --recv-keys "${FINGERPRINT_TORVALDS}" "${FINGERPRINT_GREGKH}" >/dev/null 2>&1 \
        || gpg --batch --locate-keys torvalds@kernel.org gregkh@kernel.org >/dev/null 2>&1

    echo "==> Verifying detached signature against pinned maintainer fingerprints"
    STATUS_OUT="$(xz -cd "${TAR_XZ}" | gpg --batch --status-fd=1 --verify "${TAR_SIGN}" - 2>/dev/null || true)"
    if grep -qE "^\[GNUPG:\] VALIDSIG [A-F0-9]+ .* (${FINGERPRINT_TORVALDS}|${FINGERPRINT_GREGKH})$" <<< "${STATUS_OUT}"; then
        echo "==> GPG signature verified against pinned kernel.org maintainer key."
    else
        echo "ERROR: Kernel GPG signature failed pinned fingerprint verification!" >&2
        exit 1
    fi
fi

echo "==> Extracting ${TAR_XZ} into ${DEST_DIR}"
tar --no-same-owner -xJf "${TAR_XZ}" -C "${DEST_DIR}"
echo "==> Ready: ${EXTRACT_DIR}"
