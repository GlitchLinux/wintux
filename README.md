╭──────────────────────────────────────────────╮
│ WinTux v0.6 ~ git.glitchlinux.com/wintux.git │
│ Portable bash for Windows with QEMU and CIFS │
╰──────────────────────────────────────────────╯

To get to your Windows files from the shell:

```bash
  mnt-win                   # prompts for Windows credendials
  mnt-win <user> <pass>     # non-interactive, mounts //10.0.2.2/WinTux
  mnt-win --save            # remember creds; auto-mount on next boot
  mnt-win --umount          # unmount /mnt/win
```

First time only, on the Windows side (admin cmd):

```bash
  net share WinTux="%USERPROFILE%" /GRANT:%USERNAME%,FULL
``` 

Raw-attached disks (secondary disks the launcher passed to the VM) show up as /dev/vd? and mount with ntfs-3g directly.

This is an ephemeral VM. Anything in / disappears on shutdown.
Only writes under /mnt/win reach Windows.
