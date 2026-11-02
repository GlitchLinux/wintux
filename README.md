# [![WinTux](https://github.com/user-attachments/assets/e126523a-5175-48e6-aef5-4c2afcca5e67)](https://github.com/GlitchLinux/wintux.git) WinTux - Portable Bash for Windows

**62 MB. No installer. No network. No admin. Real Linux Bash with CIFS access
to your Windows files, from a USB stick, on any Windows 10 or 11.**

```
╭───────────────────────────────────────────────────────╮
│ WinTux v1.2 ~ https://git.glitchlinux.com/wintux.git  │
│ Portable bash for Windows via QEMU + Buildroot + CIFS │
╰───────────────────────────────────────────────────────╯
```

A tiny Linux VM (Buildroot kernel + initramfs + dropbear + bash + ntfs-3g +
cifs-utils) bundled with a portable QEMU for Windows and a native Win32 GUI
launcher. Boot into a Bash shell on any Windows machine without installing
anything, enabling features, or getting admin rights. Mount a Windows SMB
share to see `/mnt/win` and work with Windows files from the shell.

## Grab a pre-built release

Download `WinTux-Portable-vX.Y.exe`, double-click, boot, go.

- https://github.com/GlitchLinux/wintux/releases/download/WinTux-Portable-v1.2/WinTux-Portable-v1.2.exe (62 MB SFX)
- https://github.com/GlitchLinux/wintux/releases/download/WinTux-Portable-v1.2/WinTux-Portable-v1.2.7z  (plain .7z)

## Flow on Windows

1. Run `WinTux.exe` (or the SFX).
2. Click **Configure WinTux Share**, enter your Windows username + password
   (or leave both empty for guest access), **Save**.
3. On the Windows side, admin cmd once:
   ```cmd
   net share WinTux="%USERPROFILE%" /GRANT:%USERNAME%,FULL
   ```
4. Click **Launch WinTux**. A GTK window pops up, the VM boots in a few
   seconds (WHPX accel) or ~30 s (TCG software emulation on Home editions
   without the Hyper-V feature).
5. Click **Open SSH Shell**. A terminal opens, you are `root@wintux:/mnt/win#`
   with your Windows home mounted.

From the Bash shell:

```bash
mnt-win                   # prompts for Windows credentials (Enter = guest)
mnt-win <user> <pass>     # non-interactive, mounts //10.0.2.2/WinTux
mnt-win --save            # remember creds; auto-mount on next boot
mnt-win --umount          # unmount /mnt/win
```

Raw-attached disks (secondary disks the launcher passed to the VM) show up
as `/dev/vd?` and mount with `ntfs-3g` directly.

Everything in `/` is RAM-only and vanishes on shutdown. Writes under
`/mnt/win` go straight to Windows via SMB and stay there.

## Repo layout

```
wintux/
├── README.md                      # you are here
├── build.sh                       # top-level build driver
├── package.sh                     # Windows-side packaging
├── bin/                           # becomes /usr/local/bin/* in the VM
│   ├── borderize                  # pretty box-drawing wrapper
│   ├── counter                    # countdown helper
│   ├── lolcat                     # colourful cat (static x86_64 ELF)
│   ├── mnt-win                    # SMB share mount helper
│   └── wintux-launch              # tty1 autologin bash launcher
├── etc/                           # becomes /etc/* in the VM
│   ├── bash.bashrc                # branded Bash greeter
│   ├── default/dropbear           # dropbear config
│   ├── init.d/S20wintux           # perms + 9p noop at boot
│   ├── init.d/S30wintux-automount # CIFS auto-mount at boot
│   ├── motd                       # /etc/motd shown by `cat /etc/motd`
│   ├── profile.d/50-wintux-login.sh # PATH + PS1 + banner + mount status + auto-mnt-win
│   └── wintux-release             # /etc/wintux-release
├── root/                          # becomes /root/* in the VM
│   └── wintux.help                # cat /root/wintux.help for a quick reference
├── buildroot/                     # Buildroot customisation (compile-time)
│   ├── board/wintux/
│   │   ├── busybox.fragment       # extra BusyBox applets
│   │   ├── grub.cfg               # GRUB menu for the ISO/USB variant
│   │   ├── linux.fragment         # kernel config: CIFS, fw_cfg, virtio, NTFS3, ...
│   │   └── post-build.sh          # fonts prune to keep rootfs lean
│   └── configs/wintux_defconfig   # Buildroot defconfig: packages, hostname, overlay, ...
├── wintux-portable/
│   ├── gui-src/
│   │   ├── 7zSD.sfx               # 7-Zip self-extractor stub
│   │   ├── main.c                 # the Win32 launcher
│   │   ├── resources.rc           # icon resource
│   │   └── wintux.ico             # 256×256 icon embedded in WinTux.exe
│   ├── wintux.ico
│   └── wintux.png
├── vendor/                        # (gitignored) QEMU-for-Windows DLL bundle
└── .work/                         # (gitignored) build output, SSH keys, Buildroot clone
```

The content model is simple: **drop a file in `bin/`, `etc/`, or `root/`,
run `./build.sh`, and it ends up inside the VM**. Kernel options go in
`buildroot/board/wintux/linux.fragment`; packages go in `buildroot/configs/wintux_defconfig`.

## Building from source

### Dependencies (Debian/Ubuntu)

```bash
sudo apt install git make gcc bison flex wget cpio xz-utils rsync bc patch \
                 unzip python3 file openssh-client p7zip-full mingw-w64
```

### Build

```bash
git clone https://git.glitchlinux.com/wintux.git
cd wintux
./build.sh
```

That's it. First run clones upstream Buildroot (pinned tag), primes the
Buildroot download cache (so you skip the ~10 min of upstream source
fetches), downloads a Bootlin pre-built cross-toolchain (so you skip the
~45 min of compiling gcc + glibc from scratch), cross-compiles the Win32
GUI, builds the kernel + rootfs, fetches the QEMU-for-Windows DLL bundle,
and assembles `.work/dist/WinTux-Portable-vX.Y.exe`.

First build is ~15-20 min with the Bootlin toolchain + primed dl cache.
Incremental rebuilds after you touch a file in `bin/` / `etc/` / `root/`
take about a minute.

### Subcommands

```bash
./build.sh clean           # wipe .work/ and start fresh
./build.sh gui             # rebuild only the Win32 launcher
./build.sh package         # repackage the SFX from current artefacts
```

### Env overrides

```bash
WINTUX_VERSION=0.9  ./build.sh                 # version in the output filename + banner
WINTUX_BUILDROOT_TAG=2026.08  ./build.sh       # which upstream Buildroot tag to use
WINTUX_JOBS=8  ./build.sh                      # parallelism
WINTUX_BASELINE_URL=https://...  ./build.sh    # alt URL for the QEMU DLL bundle
WINTUX_DL_CACHE_URL=none  ./build.sh           # skip the Buildroot dl cache priming
```

## Guest-side gotchas

- Everything in `/` is tmpfs/initramfs - **ephemeral**. Writes stay in RAM,
  disappear on shutdown. Only writes under `/mnt/win` reach Windows.
- The baked-in SSH key is generated per build host and lives in `.work/keys/`.
  It is **public** inside the shipped `.exe`: anyone who has the exe can SSH
  into the VM. Since the VM is bound to `127.0.0.1` and ephemeral, this is a
  non-issue; don't run multiple instances on a shared machine and expect
  isolation.
- Windows SMB "guest access" is disabled by default on modern Windows. To use
  the empty-password / guest flow, you need two one-time registry tweaks on
  the Windows side; or just set a real user + password and use authenticated
  mode.
- Raw-attached disks (passed via `-drive file=\\.\PhysicalDriveN,format=raw`
  on the launcher command line) appear as `/dev/vdX` and mount with ntfs-3g
  directly. Only do this for **offline** disks; mounting a volume Windows is
  actively using corrupts it.

## Comparison with the alternatives

|                             | Install?             | Network at use?       | Smallest footprint     | Real Linux kernel?       |
| --------------------------- | -------------------- | --------------------- | ---------------------- | ------------------------ |
| **WinTux**                  | **no**               | **no**                | **62 MB**              | **yes**                  |
| WSL2 (Ubuntu)               | yes, admin + Hyper-V | yes, distro fetch     | 2-3 GB after setup     | yes                      |
| Cygwin                      | yes, GUI installer   | yes, package mirror   | 400 MB+                | no (POSIX shim)          |
| MSYS2                       | yes, installer       | yes, pacman mirror    | 500 MB+                | no (POSIX shim)          |
| Git Bash (PortableGit)      | realistically installed | no at runtime      | ~400 MB                | no (MSYS runtime)        |
| Busybox-w32                 | no, single .exe      | no                    | ~1 MB                  | no (Windows binaries)    |
| Portable VirtualBox         | needs driver install | depends               | hundreds of MB + guest | yes                      |

Not the first portable Linux-in-QEMU bundle for Windows, but likely the
smallest + least friction combination of all those columns at once.

## Credits

Built on [Buildroot](https://buildroot.org/) (Linux kernel + glibc +
BusyBox + packages), [dropbear](https://matt.ucc.asn.au/dropbear/),
[ntfs-3g](https://github.com/tuxera/ntfs-3g), [cifs-utils](https://wiki.samba.org/index.php/LinuxCIFS_utils),
Stefan Weil's [QEMU for Windows](https://qemu.weilnetz.de/w64/) build,
and the [7-Zip](https://7-zip.org/) self-extractor stub.

GUI launcher and glue scripts are (c) 2026 Glitch Linux, released under
the same terms as upstream Buildroot (GPL-2.0, see individual files for
specifics).

## License

Each component carries its own upstream licence. The WinTux glue
(scripts, launcher, config fragments) is GPL-2.0.
