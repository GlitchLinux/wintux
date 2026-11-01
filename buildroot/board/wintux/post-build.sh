#!/bin/sh
# Buildroot post-build hook (BR2_ROOTFS_POST_BUILD_SCRIPT). $1 = TARGET_DIR.
# kbd installs hundreds of console fonts, which would roughly double the
# initrd. WinTux only keeps the gdisk-*.psf set from the overlay (reused
# from the GdiskOS build - they are size-labeled, not product-labeled).
set -e
T="$1"
if [ -d "$T/usr/share/consolefonts" ]; then
    find "$T/usr/share/consolefonts" -type f ! -name 'gdisk-*' ! -name 'README-fonts.txt' -delete
fi
# only needed for setfont -u / -m; our PSF fonts carry their own unicode table
rm -rf "$T/usr/share/unimaps" "$T/usr/share/consoletrans"
exit 0
