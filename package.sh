#!/bin/bash
# WinTux package.sh - assemble the Windows-side .7z and SFX .exe from build
# artefacts. Normally called by build.sh; can be run standalone to repackage
# after swapping the launcher or regenerating the rootfs.
#
# Env (inherited from build.sh):
#   WINTUX_VERSION   version string
#   WINTUX_WORK      .work dir
#   WINTUX_KEY_DIR   where wintux_key(.pub) lives
#   WINTUX_DIST      where WinTux.exe + the final .7z/.exe land

set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
# Version from env (set by build.sh), or $REPO/VERSION, or hardcoded fallback
VERSION=${WINTUX_VERSION:-$(cat "$REPO/VERSION" 2>/dev/null | head -1 | tr -d ' \t\n\r' || echo "0.9")}
WORK=${WINTUX_WORK:-$REPO/.work}
BR_OUT=$WORK/out
KEY_DIR=${WINTUX_KEY_DIR:-$WORK/keys}
DIST=${WINTUX_DIST:-$WORK/dist}

VENDOR=$REPO/vendor
QEMU_BUNDLE=$VENDOR/qemu-win.7z
QEMU_BUNDLE_URL=${WINTUX_BASELINE_URL:-https://glitchlinux.wtf/FILES/GLITCH-SOFTWARE/WinTux/vendor/qemu-win.7z}

OUT_7Z=$DIST/WinTux-Portable-v${VERSION}.7z
OUT_SFX=$DIST/WinTux-Portable-v${VERSION}.exe
GUI_EXE=$DIST/WinTux.exe
SFX_STUB=$REPO/wintux-portable/gui-src/7zSD.sfx

mkdir -p "$DIST" "$VENDOR"

# --- preflight ----------------------------------------------------------
command -v 7z >/dev/null || { echo "ERROR: 7z (p7zip-full) not found" >&2; exit 1; }
[ -f "$BR_OUT/images/bzImage"        ] || { echo "ERROR: $BR_OUT/images/bzImage missing - run build.sh first." >&2; exit 1; }
[ -f "$BR_OUT/images/rootfs.cpio.xz" ] || { echo "ERROR: $BR_OUT/images/rootfs.cpio.xz missing - run build.sh first." >&2; exit 1; }
[ -f "$GUI_EXE" ]                       || { echo "ERROR: $GUI_EXE missing - run build.sh gui." >&2; exit 1; }
[ -f "$SFX_STUB" ]                      || { echo "ERROR: $SFX_STUB missing." >&2; exit 1; }
[ -f "$KEY_DIR/wintux_key" ]            || { echo "ERROR: $KEY_DIR/wintux_key missing." >&2; exit 1; }

# --- fetch QEMU-for-Windows DLL bundle if not present -------------------
if [ ! -f "$QEMU_BUNDLE" ]; then
    echo "fetching QEMU-for-Windows DLL bundle: $QEMU_BUNDLE_URL"
    wget -q --show-progress -O "$QEMU_BUNDLE" "$QEMU_BUNDLE_URL" || {
        echo "ERROR: fetch failed. Drop a QEMU-for-Windows .7z (with qemu/ at root) at $QEMU_BUNDLE and retry." >&2
        rm -f "$QEMU_BUNDLE"
        exit 1
    }
fi

# --- staging ------------------------------------------------------------
STAGE=$(mktemp -d /tmp/wintux-package.XXXXXX)
trap "rm -rf '$STAGE'" EXIT
TREE=$STAGE/WinTux-Portable-v${VERSION}
mkdir -p "$TREE"

echo "[1/4] extracting QEMU DLL bundle"
7z x -o"$TREE" "$QEMU_BUNDLE" >/dev/null
# bundle must contain a qemu/ directory with qemu-system-x86_64.exe + DLLs
[ -f "$TREE/qemu/qemu-system-x86_64.exe" ] || {
    echo "ERROR: $QEMU_BUNDLE does not contain qemu/qemu-system-x86_64.exe" >&2
    exit 1
}

# Scrub any WinShell-era leftovers that might be in the DLL bundle
rm -f "$TREE/QEMU-Portable.exe" \
      "$TREE/qemu/winshell.bat" "$TREE/qemu/winshell-console.bat" \
      "$TREE/qemu/winshell_key" "$TREE/qemu/winshell_key.pub"
if [ -f "$TREE/qemu/boot-utilities/WinShell-x64-iPXE.iso" ]; then
    mv "$TREE/qemu/boot-utilities/WinShell-x64-iPXE.iso" "$TREE/qemu/boot-utilities/WinTux-x64-iPXE.iso"
fi

echo "[2/4] installing WinTux artefacts"
cp "$GUI_EXE"                        "$TREE/WinTux.exe"
[ -f "$DIST/WinTuxTray.exe" ] && cp "$DIST/WinTuxTray.exe" "$TREE/WinTuxTray.exe"
cp "$BR_OUT/images/bzImage"          "$TREE/qemu/bzImage"
cp "$BR_OUT/images/rootfs.cpio.xz"   "$TREE/qemu/rootfs.cpio.xz"
cp "$KEY_DIR/wintux_key"             "$TREE/qemu/wintux_key"
cp "$KEY_DIR/wintux_key.pub"         "$TREE/qemu/wintux_key.pub"
# a wintux-open-ssh.bat helper for the Open-SSH-Shell button in the launcher
cat > "$TREE/qemu/wintux-open-ssh.bat" <<'BATEOF'
@echo off
setlocal EnableDelayedExpansion
title WinTux SSH
cd /d "%~dp0"
where ssh >nul 2>&1 || (
    echo.
    echo [ERROR] OpenSSH client ^(ssh.exe^) not in PATH.
    echo Install:  Settings -^> Apps -^> Optional features -^> OpenSSH Client
    pause & exit /b 1
)
set "KEY=%~dp0wintux_key"
if not exist "%KEY%" ( echo [ERROR] wintux_key missing. & pause & exit /b 1 )
echo Connecting to WinTux VM at 127.0.0.1:2222 ...
echo ^(Retrying while the guest boots.^)
echo.
set /a tries=0
:try
set /a tries+=1
<nul set /p "=."
ssh -i "%KEY%" -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL ^
    -o IdentitiesOnly=yes -o ConnectTimeout=2 -o LogLevel=ERROR root@127.0.0.1 2>nul
if not errorlevel 1 exit /b 0
if %tries% GEQ 60 ( echo. & echo [ERROR] SSH not ready after 60 attempts. & pause & exit /b 2 )
timeout /t 1 /nobreak >nul
goto try
BATEOF

# README for the Windows package
cat > "$TREE/README.txt" <<READEOF
WinTux-Portable v$VERSION
Portable bash for Windows via QEMU + Buildroot + CIFS.
https://git.glitchlinux.com/wintux.git

Usage:
  1. Double-click WinTux.exe
  2. Click "Configure WinTux Share", enter Windows user+password (or leave
     empty for guest), Save.
  3. On the Windows side, admin cmd:   net share WinTux="%USERPROFILE%" /GRANT:%USERNAME%,FULL
  4. Click "Launch WinTux". QEMU window opens, VM boots, lands at bash.
  5. Click "Open SSH Shell" for a separate terminal.

Everything is ephemeral except what you write under /mnt/win.
READEOF

echo "[3/4] building WinTux-Portable-v${VERSION}.7z"
rm -f "$OUT_7Z"
( cd "$STAGE" && 7z a -t7z -m0=LZMA2 -mx=7 -ms=on "$OUT_7Z" "WinTux-Portable-v${VERSION}/" >/dev/null )

echo "[4/4] assembling WinTux-Portable-v${VERSION}.exe (SFX)"
FLAT=$STAGE/flat
mkdir -p "$FLAT"
cp -a "$TREE"/. "$FLAT"/
( cd "$FLAT" && 7z a -t7z -m0=LZMA2 -mx=7 -ms=on "$STAGE/payload.7z" . >/dev/null )
cat > "$STAGE/sfx_config.txt" <<'SFXEOF'
;!@Install@!UTF-8!
Title="WinTux Portable"
ExtractPathText="Extracting WinTux Portable..."
ExtractPathTitle="WinTux Portable"
ExtractDialogText="Extracting files..."
InstallPath="%TEMP%\\wintux-portable"
OverwriteMode="2"
RunProgram="WinTux.exe"
;!@InstallEnd@!
SFXEOF
cat "$SFX_STUB" "$STAGE/sfx_config.txt" "$STAGE/payload.7z" > "$OUT_SFX"
chmod 755 "$OUT_SFX"
7z t "$OUT_SFX" >/dev/null && echo "   SFX verifies OK."

echo
echo "============================================"
echo "   OUTPUTS"
echo "============================================"
ls -lh "$OUT_7Z" "$OUT_SFX"
