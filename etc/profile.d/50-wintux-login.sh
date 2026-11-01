# Single login script for WinTux: extend PATH, nicer prompt, show banner +
# mount status, and auto-run mnt-win if the share is not mounted.

export PATH="/usr/local/sbin:/usr/local/bin:$PATH"
export PS1='\u@\h:\w\$ '

# Run only once per login, and only on real TTYs (skip scp / ssh host cmd).
[ -n "$WINTUX_WELCOMED" ] && return 0
export WINTUX_WELCOMED=1
[ -t 0 ] && [ -t 1 ] || return 0

# Banner (Marcus's bash.bashrc content)
PINK=$'\033[1;35m'
BC=$'\033[1;36m'
NC=$'\033[0m'
echo
echo -e "${BC}╭────────────────────────────────────────────────────╮${NC}"
echo -e "${BC}│${NC} ${PINK}❖${NC}  WinTux v0.7 ~ git.glitchlinux.com/wintux.git ${PINK}❖${NC}  ${BC}│${NC}"
echo -e "${BC}├────────────────────────────────────────────────────┤${NC}"
echo -e "${BC}│${NC} Enables Bash shell in Windows through QEMU + CIFS  ${BC}│${NC}"
echo -e "${BC}│${NC}  Using WinTux comes with ABSOLUTELY NO WARRANTY!   ${BC}│${NC}"
echo -e "${BC}╰────────────────────────────────────────────────────╯${NC}"
echo

# Mount status / auto-mount
if mountpoint -q /mnt/win 2>/dev/null; then
    _src=$(awk '$2=="/mnt/win"{print $1}' /proc/mounts | head -1)
    echo "Windows share mounted:  $_src -> /mnt/win"
    unset _src
elif [ -z "$WINTUX_SKIP_AUTOMNT" ] && command -v mnt-win >/dev/null 2>&1; then
    echo "No Windows share mounted. Launching mnt-win..."
    echo "(Enter at the password prompt to try guest access; Ctrl-C to skip.)"
    echo
    mnt-win || true
fi
