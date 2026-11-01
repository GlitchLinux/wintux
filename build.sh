#!/bin/bash
# WinTux build.sh - the whole stack from a bare git checkout.
#
# What it does:
#   1. Clones upstream Buildroot (pinned tag) into .work/buildroot/ if missing
#   2. Composes the rootfs overlay from bin/, etc/, root/
#   3. Installs our board files (buildroot/board/wintux/*, configs/wintux_defconfig)
#   4. Generates an SSH keypair for the WinTux VM if not already generated
#   5. Builds the kernel + rootfs with make
#   6. Cross-compiles the Win32 GUI launcher (WinTux.exe) with mingw-w64
#   7. Calls package.sh which assembles the final WinTux-Portable-vX.Y.exe
#
# Requirements on the build host:
#   - Linux
#   - git, make, gcc, bison, flex, wget, cpio, xz-utils, rsync, bc, patch, unzip, python3, file
#   - mingw-w64 (x86_64-w64-mingw32-gcc and friends)   - for the GUI launcher
#   - p7zip-full (7z)                                   - for packaging
#   - ssh-keygen                                        - from openssh-client
#
# Usage:
#   ./build.sh              # full build; incremental on subsequent runs
#   ./build.sh clean        # wipe .work and start fresh
#   ./build.sh gui          # recompile just the GUI launcher
#   ./build.sh package      # just repackage from current .work artefacts
#
# Env overrides:
#   WINTUX_VERSION       (default: 0.8)      - version string baked into the package
#   WINTUX_BUILDROOT_TAG (default: 2026.08)  - upstream Buildroot tag to clone
#   WINTUX_JOBS          (default: nproc)    - parallelism for the Buildroot build
#   WINTUX_BASELINE_URL  (default: see below) - QEMU-for-Windows DLL bundle fetch URL
#   WINTUX_DL_CACHE_URL  (default: see below) - Buildroot dl cache tarball (or "none")

set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
WORK=${WINTUX_WORK:-$REPO/.work}
# Single source of truth for the version is $REPO/VERSION (one line).
# Env var WINTUX_VERSION overrides it for one-off builds.
VERSION=${WINTUX_VERSION:-$(cat "$REPO/VERSION" 2>/dev/null | head -1 | tr -d ' \t\n\r' || echo "0.9")}
BR_TAG=${WINTUX_BUILDROOT_TAG:-2026.08}
JOBS=${WINTUX_JOBS:-$(nproc 2>/dev/null || echo 4)}

BR_SRC=$WORK/buildroot
BR_OUT=$WORK/out
OVERLAY=$BR_SRC/board/wintux/overlay
KEY_DIR=$WORK/keys
DIST=$WORK/dist

# --- subcommand dispatch -------------------------------------------------

cmd=${1:-full}
case "$cmd" in
    clean)
        echo "wiping $WORK"
        rm -rf "$WORK"
        exit 0 ;;
    gui|package|full) ;;
    *) echo "usage: $0 [full|gui|package|clean]" >&2 ; exit 1 ;;
esac

mkdir -p "$WORK" "$DIST" "$KEY_DIR"

# --- step 1: fetch upstream Buildroot ------------------------------------
if [ "$cmd" = "full" ] && [ ! -d "$BR_SRC" ]; then
    echo "[1/7] cloning Buildroot $BR_TAG into $BR_SRC"
    git clone --depth 1 --branch "$BR_TAG" https://github.com/buildroot/buildroot.git "$BR_SRC"
fi

# --- step 1b: prime the Buildroot download cache if missing --------------
# Shaves ~5-10 min off a fresh build by skipping upstream source fetches.
# Set WINTUX_DL_CACHE_URL=none to disable, or point at your own mirror.
DL_URL=${WINTUX_DL_CACHE_URL:-https://glitchlinux.wtf/FILES/GLITCH-SOFTWARE/WinTux/vendor/wintux-dl-cache.tar}
if [ "$cmd" = "full" ] && [ "$DL_URL" != "none" ] && \
   { [ ! -d "$BR_SRC/dl" ] || [ -z "$(ls -A "$BR_SRC/dl" 2>/dev/null)" ]; }; then
    echo "[1b/7] priming Buildroot dl cache from $DL_URL"
    mkdir -p "$BR_SRC/dl"
    if wget -q --show-progress -O /tmp/wintux-dl.tar "$DL_URL" 2>/dev/null; then
        tar -xf /tmp/wintux-dl.tar -C "$BR_SRC"
        rm -f /tmp/wintux-dl.tar
        echo "   dl cache primed ($(du -sh "$BR_SRC/dl" | awk '{print $1}'))"
    else
        echo "   dl cache fetch failed (not fatal; Buildroot will fetch tarballs upstream)"
        rm -f /tmp/wintux-dl.tar
    fi
fi

# --- step 2: install our board files + defconfig -------------------------
if [ "$cmd" = "full" ]; then
    echo "[2/7] installing board files + defconfig into Buildroot source"
    mkdir -p "$BR_SRC/board/wintux" "$BR_SRC/configs"
    cp -a "$REPO/buildroot/board/wintux/." "$BR_SRC/board/wintux/"
    cp    "$REPO/buildroot/configs/wintux_defconfig" "$BR_SRC/configs/"
fi

# --- step 3: generate SSH keypair for the WinTux VM ----------------------
if [ ! -f "$KEY_DIR/wintux_key" ]; then
    echo "[3/7] generating fresh WinTux SSH keypair ($KEY_DIR/wintux_key)"
    ssh-keygen -t ed25519 -N "" -C "wintux-$(hostname)" -f "$KEY_DIR/wintux_key" >/dev/null
    chmod 600 "$KEY_DIR/wintux_key"
fi

# --- step 4: compose the overlay from bin/ + etc/ + root/ ----------------
if [ "$cmd" = "full" ]; then
    echo "[4/7] composing overlay at $OVERLAY"
    rm -rf "$OVERLAY"
    mkdir -p "$OVERLAY/usr/local/bin" "$OVERLAY/etc" "$OVERLAY/root/.ssh" \
             "$OVERLAY/sbin" "$OVERLAY/usr/share/consolefonts"

    cp -r "$REPO/bin/."  "$OVERLAY/usr/local/bin/"
    cp -r "$REPO/etc/."  "$OVERLAY/etc/"
    cp -r "$REPO/root/." "$OVERLAY/root/"
    chmod -R 755 "$OVERLAY/usr/local/bin/"
    chmod 755 "$OVERLAY/etc/init.d/"* 2>/dev/null || true
    chmod 644 "$OVERLAY/etc/profile.d/"* 2>/dev/null || true

    # SSH key for root
    cp "$KEY_DIR/wintux_key.pub" "$OVERLAY/root/.ssh/authorized_keys"
    chmod 700 "$OVERLAY/root/.ssh"
    chmod 644 "$OVERLAY/root/.ssh/authorized_keys"

    # mount.ntfs symlink (ntfs-3g registers mount.ntfs-3g; we also want mount.ntfs)
    ln -sf ntfs-3g "$OVERLAY/sbin/mount.ntfs"

    # Substitute the version into every overlay file that references it.
    # Matches "WinTux v<ver>" (motd/bash.bashrc banner) and "WinTux-v<ver>"
    # (filenames inside bash.bashrc / 50-wintux-login.sh). The third regex
    # rewrites WINTUX_VERSION="..." in /etc/wintux-release.
    echo "[4b/7] substituting WinTux version '$VERSION' into overlay files"
    find "$OVERLAY/etc" "$OVERLAY/root" -type f -exec sed -i -E \
        "s/WinTux v[0-9][0-9.a-zA-Z_-]*/WinTux v$VERSION/g; \
         s/WinTux-v[0-9][0-9.a-zA-Z_-]*/WinTux-v$VERSION/g; \
         s/^WINTUX_VERSION=.*/WINTUX_VERSION=\"$VERSION\"/" {} \;
fi

# --- step 5: cross-compile the GUI launcher ------------------------------
if [ "$cmd" = "full" ] || [ "$cmd" = "gui" ]; then
    echo "[5/7] cross-compiling WinTux.exe (mingw-w64)"
    command -v x86_64-w64-mingw32-gcc >/dev/null || {
        echo "ERROR: mingw-w64 not found. apt install mingw-w64" >&2; exit 1; }
    GUI_SRC=$REPO/wintux-portable/gui-src
    BUILD_GUI=$WORK/gui-build
    mkdir -p "$BUILD_GUI"
    cp "$GUI_SRC/main.c" "$GUI_SRC/resources.rc" "$GUI_SRC/wintux.ico" "$BUILD_GUI/"
    cp "$GUI_SRC/tray.c" "$BUILD_GUI/"
    ( cd "$BUILD_GUI" && \
        x86_64-w64-mingw32-windres resources.rc -o resources.o && \
        x86_64-w64-mingw32-gcc -O2 \
            -D"WINTUX_VERSION_WSTR=L\"$VERSION\"" \
            -o WinTux.exe main.c resources.o \
            -lgdi32 -lcomctl32 -lcomdlg32 -lshell32 -ladvapi32 -mwindows -municode && \
        x86_64-w64-mingw32-gcc -O2 \
            -o WinTuxTray.exe tray.c resources.o \
            -lshell32 -lgdi32 -mwindows -municode )
    cp "$BUILD_GUI/WinTuxTray.exe" "$DIST/WinTuxTray.exe"
    echo "   -> $DIST/WinTuxTray.exe ($(du -h "$BUILD_GUI/WinTuxTray.exe" | awk '{print $1}'))"
    cp "$BUILD_GUI/WinTux.exe" "$DIST/WinTux.exe"
    echo "   -> $DIST/WinTux.exe ($(du -h "$DIST/WinTux.exe" | awk '{print $1}'))"
fi

# --- step 6: build the kernel + rootfs -----------------------------------
if [ "$cmd" = "full" ]; then
    echo "[6/7] configuring + building Buildroot (this takes 20-60 min on first run)"
    mkdir -p "$BR_OUT"
    # make needs to run as a non-root user if we are root
    if [ "$(id -u)" -eq 0 ] && id -u x >/dev/null 2>&1; then
        BUILDER="sudo -u x -H"
    else
        BUILDER=""
    fi
    $BUILDER make -C "$BR_SRC" O="$BR_OUT" wintux_defconfig
    $BUILDER make -C "$BR_SRC" O="$BR_OUT" -j"$JOBS"
    echo "   artefacts in $BR_OUT/images:"
    ls -lh "$BR_OUT/images/" | sed "s/^/      /"
fi

# --- step 7: assemble the Windows-side package ---------------------------
echo "[7/7] packaging WinTux-Portable-v$VERSION"
export WINTUX_VERSION="$VERSION"
export WINTUX_WORK="$WORK"
export WINTUX_KEY_DIR="$KEY_DIR"
export WINTUX_DIST="$DIST"
exec bash "$REPO/package.sh"
