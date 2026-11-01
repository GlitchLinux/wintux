#!/bin/bash

export PATH="/usr/local/sbin:/usr/local/bin:$PATH"
export PS1='\u@\h:\w\$ '

clear

# Color definitions
PINK='\033[1;35m'
NC='\033[0m'
border_color='\033[1;36m'

cd ~
mnt-win --umount
counter 5 -l 'Unmounting Win-Drive'
mnt-win
counter 5 -l 'Mounting Win-Drive'
clear
cat >/tmp/WinTux-v0.9 <<'EOF'
╭────────────────────────────────────────────────────╮
│ ❖  WinTux v0.9 ~ git.glitchlinux.com/wintux.git ❖  │
╭────────────────────────────────────────────────────╮
│ Enables Bash shell in Windows through Qemu-Virtfs  │
│  Using WinTux comes with ABSOLUTELY NO WARRANTY!   │
╰────────────────────────────────────────────────────╯
EOF
cat /tmp/WinTux-v0.9 | lolcat
cd /mnt/
cd win/
