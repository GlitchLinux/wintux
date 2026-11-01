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
mnt-win Admin 9880
counter 5 -l 'Mounting Win-Drive'
clear
cat >/tmp/WinTux-v0.7 <<'EOF'
�^u��^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�>
�^t^b �^}^v  WinTux v0.7 ~ git.glitchlinux.com/wintux.git �^}^v  �^t^b
�^u��^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�>
�^t^b Enables Bash shell in Windows through Qemu-Virtfs  �^t^b
�^t^b  Using WinTux comes with ABSOLUTELY NO WARRANTY!   �^t^b
�^u��^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�^t^`�>
EOF
cat /tmp/WinTux-v0.7 | lolcat
cd /mnt/
cd win/
