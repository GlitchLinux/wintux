#!/bin/bash
cat > /etc/bash.bashrc <<'HEADER'
#!/bin/bash

export PATH="/usr/local/sbin:/usr/local/bin:$PATH"
export PS1='\u@\h:\w\$ '

clear

# Color definitions
PINK='\033[1;35m'
NC='\033[0m'
border_color='\033[1;36m'

WINMOUNT="/mnt/win"
if mountpoint -d "$WINMOUNT"; then
        cd ~ && clear
        mnt-win --umount | counter 5 -l 'Unmounting /mnt/win/'
fi
clear
mnt-win
clear
counter 5 -l 'Mounting /mnt/wim/'
clear
cat >/tmp/WinTux-v1.1 <<'EOF'
╭────────────────────────────────────────────────────╮
│ ❖  WinTux v1.1 ~ git.glitchlinux.com/wintux.git ❖  │
╭────────────────────────────────────────────────────╮
│ Enables Bash shell in Windows through Qemu-Virtfs  │
│  Using WinTux comes with ABSOLUTELY NO WARRANTY!   │
╰────────────────────────────────────────────────────╯
EOF
cat /tmp/WinTux-v1.1 | lolcat
cd /mnt/win
HEADER

bash /usr/local/bin/mnt-win-all &

chmod +x /etc/bash.bashrc
clear
source /etc/bash.bashrc