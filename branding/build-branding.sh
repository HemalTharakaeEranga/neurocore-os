#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Compiles master NeuroCore OS dark-adapted penguin-and-gear assets across all
# five OS visual surfaces and stages them into mkosi/mkosi.extra/:
#   1. Linux kernel early framebuffer boot logo (logo_linux_clut224.ppm)
#   2. GRUB2 dark #0b0f14 boot menu theme + PF2 fonts
#   3. Plymouth animated boot splash (frame-000.png .. frame-NNN.png)
#   4. FreeDesktop hicolor icon hierarchy (scalable SVG + 16..256 PNGs)
#   5. Dynamic MOTD (/etc/update-motd.d/10-neurocore)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${SCRIPT_DIR}/source"
GEN_DIR="${SCRIPT_DIR}/generated"
EXTRA_DIR="${REPO_ROOT}/mkosi/mkosi.extra"

LOGO_PNG="${SRC_DIR}/neurocore-logo-1024.png"
LOGO_SVG="${SRC_DIR}/neurocore-logo.svg"
BOOT_GIF="${SRC_DIR}/neurocore-boot.gif"

if command -v magick >/dev/null 2>&1; then
    IM_CMD=(magick)
elif command -v convert >/dev/null 2>&1; then
    IM_CMD=(convert)
else
    echo "ERROR: ImageMagick ('magick' or 'convert') is required." >&2
    exit 1
fi

rm -rf "${GEN_DIR}"
mkdir -p \
    "${GEN_DIR}/kernel" \
    "${GEN_DIR}/grub" \
    "${GEN_DIR}/plymouth" \
    "${GEN_DIR}/icons/hicolor/scalable/apps"

# --- Surface 1: Linux Kernel CLUT224 Framebuffer Boot Logo (128x128 ASCII P3 PPM <=224 colors) ---
echo "==> [1/5] Generating kernel logo_linux_clut224.ppm (128x128 on #0b0f14)"
"${IM_CMD[@]}" "${LOGO_PNG}" \
    -background "#0b0f14" -flatten \
    -resize 128x128 \
    -colors 224 \
    -compress none \
    "PPM:${GEN_DIR}/kernel/logo_linux_clut224.ppm"

# --- Surface 2: GRUB2 Dark Boot Menu Theme ---
echo "==> [2/5] Generating GRUB2 theme assets"
cp -f "${SCRIPT_DIR}/grub/theme.txt" "${GEN_DIR}/grub/theme.txt"
"${IM_CMD[@]}" -size 1920x1080 xc:"#0b0f14" -interlace none "PNG24:${GEN_DIR}/grub/background.png"
"${IM_CMD[@]}" "${LOGO_PNG}" \
    -background "#0b0f14" -flatten \
    -resize 128x128 -interlace none \
    "PNG24:${GEN_DIR}/grub/logo.png"

if command -v grub-mkfont >/dev/null 2>&1; then
    FONT_MONO="/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
    FONT_SANS="/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    FONT_BOLD="/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    [[ -f "${FONT_MONO}" ]] && grub-mkfont -s 14 -o "${GEN_DIR}/grub/dejavu_sans_mono_14.pf2" "${FONT_MONO}"
    [[ -f "${FONT_SANS}" ]] && grub-mkfont -s 16 -o "${GEN_DIR}/grub/dejavu_sans_16.pf2" "${FONT_SANS}"
    [[ -f "${FONT_BOLD}" ]] && grub-mkfont -s 20 -o "${GEN_DIR}/grub/dejavu_sans_bold_20.pf2" "${FONT_BOLD}"
else
    echo "    [WARN] grub-mkfont not found; skipping .pf2 generation"
fi

# --- Surface 3: Plymouth Animated Boot Splash (dark-adapted 256x256 RGBA PNG sequence) ---
echo "==> [3/5] Generating dark-adapted Plymouth animation frames from neurocore-boot.gif"
FRAME_COUNT="$(python3 "${SCRIPT_DIR}/scripts/adapt_branding.py" \
    --gif "${BOOT_GIF}" \
    --out-dir "${GEN_DIR}/plymouth" \
    --size 256)"
echo "    Extracted and dark-adapted ${FRAME_COUNT} frames"

"${IM_CMD[@]}" "${LOGO_PNG}" -resize 256x256 "PNG32:${GEN_DIR}/plymouth/logo.png"
cp -f "${SCRIPT_DIR}/plymouth/neurocore.plymouth" "${GEN_DIR}/plymouth/neurocore.plymouth"
sed "s/^frame_count = [0-9]\+;/frame_count = ${FRAME_COUNT};/" \
    "${SCRIPT_DIR}/plymouth/neurocore.script" > "${GEN_DIR}/plymouth/neurocore.script"

# --- Surface 4: FreeDesktop hicolor Icon Hierarchy ---
echo "==> [4/5] Generating FreeDesktop hicolor icons (SVG in scalable/ ONLY + PNGs 16..256)"
cp -f "${LOGO_SVG}" "${GEN_DIR}/icons/hicolor/scalable/apps/neurocore-logo.svg"
for sz in 16 24 32 48 64 128 256; do
    dir="${GEN_DIR}/icons/hicolor/${sz}x${sz}/apps"
    mkdir -p "${dir}"
    "${IM_CMD[@]}" "${LOGO_PNG}" -resize "${sz}x${sz}" "PNG32:${dir}/neurocore-logo.png"
done

# --- Surface 5: Stage all generated branding assets into mkosi/mkosi.extra ---
echo "==> [5/5] Staging branding assets into ${EXTRA_DIR}"
mkdir -p \
    "${EXTRA_DIR}/boot/grub/themes/neurocore" \
    "${EXTRA_DIR}/usr/share/plymouth/themes/neurocore" \
    "${EXTRA_DIR}/usr/share/icons/hicolor" \
    "${EXTRA_DIR}/etc/update-motd.d"

cp -a "${GEN_DIR}/grub/." "${EXTRA_DIR}/boot/grub/themes/neurocore/"
cp -a "${GEN_DIR}/plymouth/." "${EXTRA_DIR}/usr/share/plymouth/themes/neurocore/"
cp -a "${GEN_DIR}/icons/hicolor/." "${EXTRA_DIR}/usr/share/icons/hicolor/"
install -m 0755 "${SCRIPT_DIR}/motd/10-neurocore" "${EXTRA_DIR}/etc/update-motd.d/10-neurocore"

echo "==> Branding pipeline completed cleanly (all 5 OS visual surfaces ready)."
