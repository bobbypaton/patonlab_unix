#!/bin/bash
#
# Read-only health, maintenance and safety audit of one group workstation.
#
# Prints one finding per line:  SEVERITY|CATEGORY|CHECK|MESSAGE
#   CRIT  needs action now (data at risk, security hole, machine unhealthy)
#   WARN  should be fixed soon
#   INFO  worth knowing
#   OK    check passed
#   META  facts about the machine (OS, hardware) for the report header
#
# Changes nothing and writes no files. Most checks work as a normal user; run as
# root (sudo) to add disk SMART health, sshd settings, backup contents and
# account passwords. Normally run for every machine by admin/audit_machines:
#     ssh host 'bash -s' < admin/audit_host.sh
#
# Expected versions and thresholds can be overridden with environment variables
# (EXPECT_ORCA, EXPECT_XTB, EXPECT_CREST, EXPECT_GXTB, EXPECT_OPENMPI,
# DISK_WARN, DISK_CRIT, BACKUP_MAX_DAYS, FIND_TIMEOUT, and IGNORE_ADMINS: admin
# accounts not to flag as unused, e.g. an IT department's account).
#
# Works with bash 4.2 (CentOS 7) and later.
#
# Author: Paton Research Group (patonlab@colostate.edu)

export PATH="$PATH:/usr/sbin:/sbin:/usr/local/sbin:/usr/local/bin"
export LC_ALL=C

EXPECT_ORCA=${EXPECT_ORCA:-6.1.0}
EXPECT_XTB=${EXPECT_XTB:-6.7.1}
EXPECT_CREST=${EXPECT_CREST:-3.0.2}
EXPECT_GXTB=${EXPECT_GXTB:-2.0.1}
EXPECT_OPENMPI=${EXPECT_OPENMPI:-4.1.8}
REPO_URL=${REPO_URL:-https://github.com/bobbypaton/patonlab_unix}
DISK_WARN=${DISK_WARN:-80}
DISK_CRIT=${DISK_CRIT:-90}
BACKUP_MAX_DAYS=${BACKUP_MAX_DAYS:-8}
FIND_TIMEOUT=${FIND_TIMEOUT:-300}
IGNORE_ADMINS=${IGNORE_ADMINS:-}

R=/usr/local/patonlab_unix
MAINT=/usr/local/Maintainence_Scripts   # where the weekly backup script lives
IS_ROOT=0; [ "$(id -u)" -eq 0 ] && IS_ROOT=1
NOW=$(date +%s)

out() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"; }
have() { command -v "$1" >/dev/null 2>&1; }
tfind() { timeout "$FIND_TIMEOUT" find "$@" 2>/dev/null; }
days_since() { echo $(( (NOW - $1) / 86400 )); }
join() { local IFS=" "; echo "$*"; }
plural() { [ "$1" -eq 1 ] && echo "$1 $2" || echo "$1 ${3:-${2}s}"; }

# ============================== Machine facts ==============================

. /etc/os-release 2>/dev/null
# Package family from the OS itself (a CentOS machine can have an apt-get command installed)
case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "*|*" ubuntu "*) PKG=apt ;;
    *" rhel "*|*" centos "*|*" fedora "*) PKG=rpm ;;
    *) PKG=unknown ;;
esac
CORES=$(nproc 2>/dev/null || echo 1)
MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
out META host name "$(hostname -s)"
out META host os "${PRETTY_NAME:-unknown}, kernel $(uname -r)"
out META host hardware "$CORES CPU threads, $(( MEM_KB / 1048576 )) GiB RAM"
out META host uptime "$(uptime -p 2>/dev/null || uptime | sed 's/.*up/up/; s/,  *[0-9]* user.*//')"
out META host auditor "$(id -un)$([ $IS_ROOT -eq 1 ] && echo ' (root: all checks)' || echo ' (not root: root-only checks skipped)')"

# ============================== Maintenance ==============================

check_os() {
    local eol="" left
    case "${ID:-}:${VERSION_ID:-}" in
        centos:7*) eol=2024-06-30 ;;
        centos:8*) if [ "${NAME:-}" = "CentOS Stream" ]; then eol=2024-05-31; else eol=2021-12-31; fi ;;
        ubuntu:18.04) eol=2023-05-31 ;;
        ubuntu:20.04) eol=2025-05-31 ;;
        ubuntu:22.04) eol=2027-04-30 ;;
        ubuntu:24.04) eol=2029-04-30 ;;
        rocky:8*|almalinux:8*|rhel:8*) eol=2029-05-31 ;;
        rocky:9*|almalinux:9*|rhel:9*) eol=2032-05-31 ;;
    esac
    if [ -z "$eol" ]; then
        out INFO Maintenance os "${PRETTY_NAME:-unknown OS}: end-of-support date not known to this script"
    else
        left=$(( ($(date -d "$eol" +%s) - NOW) / 86400 ))
        if [ $left -lt 0 ]; then
            out CRIT Maintenance os "${PRETTY_NAME} reached end of life on $eol: no security updates"
        elif [ $left -lt 90 ]; then
            out WARN Maintenance os "${PRETTY_NAME} support ends $eol ($left days): plan the upgrade"
        elif [ $left -lt 365 ]; then
            out INFO Maintenance os "${PRETTY_NAME} support ends $eol ($left days)"
        else
            out OK Maintenance os "${PRETTY_NAME}, supported until $eol"
        fi
    fi
    # An EL7 kernel under an EL8 userland means an upgrade was left half done
    case "$(uname -r):${VERSION_ID:-}" in
        *el7*:8*) out WARN Maintenance os-half-upgrade "running an EL7 kernel ($(uname -r)) on an EL8 system: half-finished upgrade" ;;
    esac
}

check_updates() {
    if [ "$PKG" = apt ]; then
        local sim pending security
        sim=$(apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null | grep '^Inst')
        pending=$(printf '%s' "$sim" | grep -c '^Inst')
        security=$(printf '%s' "$sim" | grep -c -- '-security')
        if [ "$security" -gt 0 ]; then
            out WARN Maintenance updates "$pending updates waiting, $security of them security (sudo apt full-upgrade)"
        elif [ "$pending" -gt 50 ]; then
            out WARN Maintenance updates "$pending updates waiting (sudo apt full-upgrade)"
        elif [ "$pending" -gt 0 ]; then
            out INFO Maintenance updates "$pending updates waiting"
        else
            out OK Maintenance updates "no updates waiting"
        fi
        if [ -e /var/run/reboot-required ]; then
            out WARN Maintenance reboot "reboot required for: $(sort -u /var/run/reboot-required.pkgs 2>/dev/null | head -5 | tr '\n' ' ')"
        fi
        if [ "$(systemctl is-enabled unattended-upgrades 2>/dev/null)" != enabled ]; then
            out WARN Maintenance auto-updates "unattended-upgrades is not enabled"
        elif [ -r /var/log/unattended-upgrades/unattended-upgrades.log ] &&
             tail -1 /var/log/unattended-upgrades/unattended-upgrades.log | grep -q "on battery"; then
            out CRIT Maintenance auto-updates "automatic updates are stopping: 'System is on battery power' (set Unattended-Upgrade::OnlyOnACPower \"false\")"
        fi
    elif [ "$PKG" = rpm ]; then
        local last newest
        last=$(rpm -qa --qf '%{INSTALLTIME}\n' 2>/dev/null | sort -n | tail -1)
        [ -n "$last" ] && out INFO Maintenance updates "last package installed $(days_since "$last") days ago"
        newest=$(rpm -q --last kernel 2>/dev/null | head -1 | awk '{print $1}' | sed 's/^kernel-//')
        if [ -n "$newest" ] && [ "$newest" != "$(uname -r)" ]; then
            out WARN Maintenance reboot "newer kernel installed ($newest) than running ($(uname -r)): reboot needed"
        fi
    fi
    local up
    up=$(awk '{print int($1/86400)}' /proc/uptime)
    [ "$up" -gt 180 ] && out INFO Maintenance uptime "up $up days without a reboot"
}

check_services() {
    local failed
    failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | grep -v '^snap-' | tr '\n' ' ')
    if [ -n "$failed" ]; then
        out WARN Maintenance services "failed services: $failed"
    else
        out OK Maintenance services "no failed services"
    fi
    local sync
    sync=$(timedatectl status 2>/dev/null | awk -F': ' '/synchronized:/ {print $2}' | head -1)
    [ "$sync" = no ] && out WARN Maintenance clock "system clock is not synchronised (NTP)"
}

check_disks() {
    local bad=0 size used pct mnt
    while read -r _ size used _ pct mnt; do
        pct=${pct%\%}
        case "$pct" in ''|*[!0-9]*) continue ;; esac
        if [ "$pct" -ge "$DISK_CRIT" ]; then
            out CRIT Disks "space $mnt" "$mnt is $pct% full ($used of $size used)"; bad=1
        elif [ "$pct" -ge "$DISK_WARN" ]; then
            out WARN Disks "space $mnt" "$mnt is $pct% full ($used of $size used)"; bad=1
        fi
    done < <(df -hP -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x iso9660 2>/dev/null | tail -n +2)
    while read -r _ _ _ _ pct mnt; do
        pct=${pct%\%}
        case "$pct" in ''|*[!0-9]*) continue ;; esac
        [ "$pct" -ge 90 ] && { out WARN Disks "inodes $mnt" "$mnt has used $pct% of its inodes (file slots)"; bad=1; }
    done < <(df -iP -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs -x iso9660 -x vfat 2>/dev/null | tail -n +2)
    [ $bad -eq 0 ] && out OK Disks space "all filesystems below $DISK_WARN% full"

    if [ -r /proc/mdstat ] && grep -q '^md' /proc/mdstat; then
        if grep -qE '\[[U_]*_[U_]*\]' /proc/mdstat; then
            out CRIT Disks raid "software RAID is degraded: $(grep -E '^md|\[[U_]*_' /proc/mdstat | tr -s ' ' | tr '\n' ' ')"
        elif grep -qE 'resync|recovery' /proc/mdstat; then
            out INFO Disks raid "software RAID is rebuilding"
        else
            out OK Disks raid "software RAID healthy"
        fi
    fi

    if [ $IS_ROOT -eq 1 ] && have smartctl; then
        local d health
        for d in $(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print $1}'); do
            health=$(smartctl -H /dev/$d 2>/dev/null | grep -iE 'overall-health|SMART Health Status' | sed 's/.*: *//')
            [ -z "$health" ] && health=$(smartctl -d sat -H /dev/$d 2>/dev/null | grep -iE 'overall-health' | sed 's/.*: *//')
            case "$health" in
                PASSED|OK) ;;
                "") out INFO Disks "smart $d" "no SMART health reported for /dev/$d" ;;
                *) out CRIT Disks "smart $d" "/dev/$d SMART health: $health (replace the drive)" ;;
            esac
        done
    elif [ $IS_ROOT -eq 0 ]; then
        out INFO Disks smart "drive SMART health not checked (needs root)"
    fi
}

check_backups() {
    local log=$MAINT/backup_log.txt script=$MAINT/BackupScript.sh mode age
    if [ -d /mnt/backups ]; then
        mode=$(stat -c %a /mnt/backups)
        local fstype
        fstype=$(df -PT /mnt/backups 2>/dev/null | awk 'NR==2 {print $2}')
        case "$mode:$fstype" in
            *[1-7]:exfat|*[1-7]:vfat|*[1-7]:fuseblk|*[1-7]:ntfs*)
                out CRIT Backups permissions "/mnt/backups ($fstype) is mode $mode: every user can read the backups; $fstype has no Unix permissions, so mount it with umask=077 or reformat as ext4" ;;
            *[1-7]:*) out CRIT Backups permissions "/mnt/backups is mode $mode: every user can read everyone's backed-up files (chmod 700)" ;;
            *) out OK Backups permissions "/mnt/backups is root-only" ;;
        esac
        if [ -f "$log" ]; then
            case "$(stat -c %a "$log")" in
                *[4-7]) out WARN Backups log "$log is readable by everyone (it lists every backed-up file; chmod 600)" ;;
            esac
            age=$(days_since "$(stat -c %Y "$log")")
            if [ "$age" -gt "$BACKUP_MAX_DAYS" ]; then
                out CRIT Backups age "last backup finished $age days ago: the weekly backup has stopped"
            else
                out OK Backups age "last backup finished $age days ago"
            fi
        else
            out WARN Backups age "no $log: can't tell when the last backup ran"
        fi
        [ -f "$script" ] && ! grep -q '^umask 077' "$script" &&
            out WARN Backups script "$script has no 'umask 077': new archives will be readable by everyone"
        if [ $IS_ROOT -eq 1 ]; then
            local newest
            newest=$(ls -td /mnt/backups/*_Backup 2>/dev/null | head -1)
            if [ -n "$newest" ] && [ ! -s "$newest/home_backup.tgz" ]; then
                out CRIT Backups contents "$newest has no (or an empty) home_backup.tgz"
            fi
        fi
    else
        out WARN Backups none "no backup found on this machine (no /mnt/backups)"
    fi
}

check_group_setup() {
    if [ ! -d "$R/.git" ]; then
        out WARN Software patonlab_unix "$R is not installed"
    else
        local here remote edits owner
        here=$(cd "$R" && git -c safe.directory="$R" rev-parse HEAD 2>/dev/null)
        edits=$(cd "$R" && git -c safe.directory="$R" status --porcelain 2>/dev/null | wc -l)
        owner=$(stat -c %U "$R")
        remote=$(timeout 30 git ls-remote "$REPO_URL" refs/heads/main 2>/dev/null | awk '{print $1}')
        if [ -n "$remote" ] && [ "$remote" != "$here" ]; then
            out WARN Software patonlab_unix "group scripts at ${here:0:7}, GitHub main is ${remote:0:7}: update them"
        elif [ -n "$remote" ]; then
            out OK Software patonlab_unix "group scripts up to date (${here:0:7})"
        else
            out INFO Software patonlab_unix "group scripts at ${here:0:7} (couldn't reach GitHub to compare)"
        fi
        [ "$edits" -gt 0 ] && out WARN Software patonlab_unix-edits "$(plural "$edits" "locally edited file") in $R (commit changes to the repository instead)"
        [ "$owner" != root ] && out WARN Software patonlab_unix-owner "$R is owned by $owner, not root"
    fi
    [ -e /etc/profile.d/patonlab.sh ] || out INFO Software profile "group login profile not installed (/etc/profile.d/patonlab.sh)"
    if grep -q 'checked by autotest' /etc/motd 2>/dev/null; then
        local motd_age
        motd_age=$(days_since "$(stat -c %Y /etc/motd)")
        [ "$motd_age" -gt 120 ] && out INFO Software motd "MOTD software status is $motd_age days old (re-run admin/make_motd)"
    else
        out INFO Software motd "MOTD not generated by admin/make_motd"
    fi
}

check_versions() {
    local v
    if [ -x /usr/local/ORCA6/orca ]; then
        v=$(grep -m1 -aoE 'Program Version [0-9.]+' /usr/local/ORCA6/orca | awk '{print $3}')
        [ "$v" != "$EXPECT_ORCA" ] && out WARN Software orca "ORCA is ${v:-unknown}, group standard is $EXPECT_ORCA"
    else
        out INFO Software orca "no ORCA at /usr/local/ORCA6"
    fi
    if [ -x /usr/local/xtb/bin/xtb ]; then
        v=$(/usr/local/xtb/bin/xtb --version 2>&1 | grep -m1 -oE 'version [0-9.]+' | cut -d' ' -f2)
        [ "$v" != "$EXPECT_XTB" ] && out WARN Software xtb "xtb is ${v:-unknown}, group standard is $EXPECT_XTB (admin/install_software.sh --xtb)"
    fi
    local c=/usr/local/crest/crest
    [ -x $c ] || c=/usr/local/xtb/crest
    if [ -x $c ]; then
        v=$($c --version 2>&1 | grep -m1 -oE 'Version [0-9.a-z]+' | cut -d' ' -f2)
        [ "$v" != "$EXPECT_CREST" ] && out WARN Software crest "CREST is ${v:-unknown}, group standard is $EXPECT_CREST (admin/install_software.sh --crest)"
    fi
    if [ -x /usr/local/g-xtb/xtb-gxtb ]; then
        v=$(basename "$(readlink -f /usr/local/g-xtb)" | sed 's/^g-xtb-//')
        [ "$v" != "$EXPECT_GXTB" ] && out INFO Software gxtb "g-xTB is $v, group standard is $EXPECT_GXTB"
    else
        out INFO Software gxtb "g-xTB $EXPECT_GXTB not installed (admin/install_software.sh --gxtb)"
    fi
    if [ -x /opt/openmpi/bin/mpirun ]; then
        v=$(env -i PATH=/usr/bin:/bin /opt/openmpi/bin/mpirun --version 2>&1 | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+')
        [ "$v" != "$EXPECT_OPENMPI" ] && out WARN Software openmpi "/opt/openmpi is OpenMPI ${v:-unknown}, group standard is $EXPECT_OPENMPI"
    else
        out INFO Software openmpi "no /opt/openmpi (admin/install_software.sh --openmpi)"
    fi
    local old
    old=$(ls -d /usr/local/ORCA5* /usr/local/orca_5* /usr/local/orca_6_0* 2>/dev/null | tr '\n' ' ')
    [ -n "$old" ] && out INFO Software leftovers-orca "old ORCA versions still installed: $old"
    local d stale=""
    for d in /usr/local/*.pre-* /opt/*.pre-*; do
        [ -e "$d" ] || continue
        # Age from the date in the name (moving a folder keeps its old modification time)
        local stamp=${d##*.pre-}
        case "$stamp" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) continue ;; esac
        [ "$(days_since "$(date -d "$stamp" +%s)")" -gt 30 ] && stale="$stale $(basename "$d")"
    done
    [ -n "$stale" ] && out INFO Software leftovers-pre "replaced installs kept for over 30 days (delete if all is well):$stale"
}

# ============================== Safety ==============================

check_world_writable() {
    # World-writable files in shared software: anyone could change programs others run
    local t n bad=0 seen=" "
    for t in /usr/local/bin /usr/local/sbin /usr/local/ORCA6 /usr/local/orca_* /usr/local/xtb /usr/local/crest \
             /usr/local/g-xtb* /usr/local/nbo7 /usr/local/qchem* /usr/local/nciplot /usr/local/Gaussian \
             /usr/local/BIOVIA /usr/local/patonlab_unix /opt /apps; do
        [ -e "$t" ] || continue
        t=$(readlink -f "$t")
        case "$seen" in *" $t "*) continue ;; esac
        seen="$seen$t "
        # Sticky world-writable directories (like /tmp) are fine: users can't touch each other's files
        n=$(tfind "$t" -xdev -perm -o+w ! -type l ! \( -type d -perm -1000 \) | head -100000 | wc -l)
        [ "$n" -eq 0 ] && continue
        bad=1
        case "$t" in
            /usr/local/bin|/usr/local/sbin)
                out CRIT Safety "world-writable $t" "$(plural "$n" "world-writable file") in $t (on everyone's PATH): $(tfind "$t" -maxdepth 1 -perm -o+w ! -type l | head -3 | tr '\n' ' ')" ;;
            *)  out WARN Safety "world-writable $t" "$(plural "$n" "world-writable file") under $t (chmod -R o-w, or find -perm -o+w -exec chmod o-w)" ;;
        esac
    done
    [ $bad -eq 0 ] && out OK Safety world-writable "no world-writable files in shared software"
    # World-writable directories without the sticky bit: anyone can delete or rename others' files
    local d
    for d in $(tfind / -xdev -maxdepth 2 -type d -perm -0002 ! -perm -1000 ! -path '/tmp/*' ! -path '/var/tmp/*'); do
        out WARN Safety "sticky $d" "$d is world-writable without the sticky bit: anyone can delete others' files (chmod 1777)"
    done
}

check_ownership() {
    local d owner bad=""
    for d in /usr/local/ORCA6 /usr/local/xtb /usr/local/crest /usr/local/g-xtb /usr/local/nbo7 \
             /usr/local/qchem6 /usr/local/qchem7 /usr/local/nciplot /opt/openmpi; do
        [ -e "$d" ] || continue
        owner=$(stat -c %U "$(readlink -f "$d")")
        [ "$owner" != root ] && bad="$bad $d($owner)"
    done
    [ -n "$bad" ] && out WARN Safety ownership "shared software not owned by root (that account can change it for everyone):$bad"

    local g mode
    for g in /usr/local/Gaussian/*/g16; do
        [ -e "$g" ] || continue
        g=$(readlink -f "$g")
        mode=$(stat -c %a "$g")
        case "$mode" in
            *[1-7]) out WARN Safety "gaussian-mode $g" "$g is mode $mode: readable by every account (Gaussian's licence requires a group; chmod o-rwx)" ;;
        esac
        case "$(stat -c %A "$g")" in
            ?????w????) out WARN Safety "gaussian-group-writable $g" "$g is group-writable: group members can change the programs (chmod -R g-w)" ;;
        esac
        [ "$(stat -c %G "$g")" = "$(stat -c %U "$g")" ] && [ "$(stat -c %U "$g")" != root ] &&
            out WARN Safety "gaussian-private-group $g" "$g belongs to $(stat -c %U "$g")'s private group: only that account can run Gaussian (use a gaussian group)"
    done
    if [ -e /usr/local/ORCA6 ]; then
        case "$(stat -c %A "$(readlink -f /usr/local/ORCA6)")" in
            ???????r?x) ;;
            *) out WARN Safety orca "/usr/local/ORCA6 is not readable by other accounts: only its owner can run ORCA" ;;
        esac
    fi
    local lic
    for lic in /usr/local/qchem*/qcaux/license/qchem.license.dat; do
        [ -e "$lic" ] || continue
        case "$(stat -c %a "$(readlink -f "$lic")")" in
            *[4-7]) ;;
            *) out WARN Safety "qchem-licence $lic" "$lic is not readable by other accounts: only its owner can run Q-Chem (chmod 644)" ;;
        esac
    done
}

check_firewall() {
    if have ufw || [ -f /etc/ufw/ufw.conf ]; then
        if grep -q '^ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null; then
            out OK Safety firewall "ufw enabled"
        else
            out WARN Safety firewall "firewall off (sudo ufw allow OpenSSH && sudo ufw enable)"
        fi
    elif systemctl list-unit-files firewalld.service >/dev/null 2>&1 && systemctl cat firewalld >/dev/null 2>&1; then
        if [ "$(systemctl is-active firewalld 2>/dev/null)" = active ]; then
            out OK Safety firewall "firewalld active"
        else
            out WARN Safety firewall "firewalld not running"
        fi
    else
        out WARN Safety firewall "no firewall (ufw or firewalld) found"
    fi
    if [ $IS_ROOT -eq 1 ] && have sshd; then
        local cfg
        cfg=$(sshd -T 2>/dev/null)
        printf '%s\n' "$cfg" | grep -qi '^permitrootlogin yes' && out WARN Safety ssh-root-login "sshd allows root to log in with a password (PermitRootLogin yes)"
        printf '%s\n' "$cfg" | grep -qi '^passwordauthentication yes' && out INFO Safety ssh-passwords "sshd accepts passwords (consider keys only)"
    fi
}

check_accounts() {
    local admins a n=0 unused=""
    admins=$(getent group sudo wheel 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -v '^root$' | grep -v '^$' | sort -u)
    for a in $admins; do
        n=$((n+1))
        case " $IGNORE_ADMINS " in *" $a "*) continue ;; esac
        lastlog -u "$a" 2>/dev/null | tail -1 | grep -q 'Never logged in' && unused="$unused $a(never)"
    done
    for a in $(lastlog -b 365 2>/dev/null | awk 'NR>1 {print $1}'); do
        case " $IGNORE_ADMINS " in *" $a "*) continue ;; esac
        case " $(join $admins) " in *" $a "*) case "$unused" in *" $a("*) ;; *) unused="$unused $a(>1 year)";; esac ;; esac
    done
    [ $n -gt 4 ] && out WARN Safety admins-count "$n accounts have sudo: $(join $admins)"
    [ -n "$unused" ] && out WARN Safety admins-unused "admin accounts not used for a year or never:$unused (remove from sudo/wheel or lock)"
    local stale
    stale=$(lastlog -b 365 2>/dev/null | awk 'NR>1 {print $1}' | while read -r u; do
        i=$(id -u "$u" 2>/dev/null) && [ "$i" -ge 1000 ] && [ "$i" -lt 60000 ] && echo "$u"; done | wc -l)
    [ "$stale" -gt 0 ] && out INFO Safety accounts-stale "$(plural "$stale" account) with no login for a year (lock them: usermod -L -e 1)"
    local h mode
    for h in /home/*; do
        [ -d "$h" ] || continue
        mode=$(stat -c %a "$h")
        case "$mode" in
            *[2367]) out CRIT Safety "home $h" "$h is mode $mode: anyone can delete or replace that user's files (chmod 700)" ;;
        esac
    done
    if [ $IS_ROOT -eq 1 ]; then
        local empty
        empty=$(awk -F: '$2=="" {print $1}' /etc/shadow 2>/dev/null | tr '\n' ' ')
        [ -n "$empty" ] && out CRIT Safety accounts-no-password "accounts with no password: $empty"
    fi
}

check_my_ssh() {
    # The auditing account's own SSH files (other users' are private)
    local s=$HOME/.ssh k n
    [ -d "$s" ] || return
    case "$(stat -c %a "$s")" in 700) ;; *) out WARN Safety my-ssh-dir "$s is mode $(stat -c %a "$s") (chmod 700)" ;; esac
    if [ -f "$s/authorized_keys" ]; then
        case "$(stat -c %a "$s/authorized_keys")" in 600|400) ;; *) out WARN Safety my-ssh-authorized-keys "$s/authorized_keys is mode $(stat -c %a "$s/authorized_keys") (chmod 600)" ;; esac
        n=$(grep -cvE '^\s*(#|$)' "$s/authorized_keys")
        [ "$n" -gt 10 ] && out INFO Safety my-ssh-key-count "$(plural "$n" key) can log in as $(id -un) here (remove ones you don't recognise)"
    fi
    for k in "$s"/id_*; do
        [ -f "$k" ] || continue
        case "$k" in *.pub) continue ;; esac
        ssh-keygen -y -P "" -f "$k" >/dev/null 2>&1 &&
            out WARN Safety "my-ssh-key $(basename "$k")" "private key $k has no passphrase (anyone who copies it can use it)"
    done
}

# ============================== Performance ==============================

check_performance() {
    local l15 avail swap_total swap_free
    l15=$(awk '{print $3}' /proc/loadavg)
    awk -v l="$l15" -v c="$CORES" 'BEGIN {exit !(l > 1.25 * c)}' &&
        out WARN Performance load "15-minute load is $l15 on $CORES CPU threads: jobs are oversubscribed"
    avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    [ -n "$avail" ] && [ "$avail" -lt $(( MEM_KB / 20 )) ] &&
        out WARN Performance memory-available "only $(( avail / 1024 )) MiB of memory available"
    swap_total=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
    swap_free=$(awk '/SwapFree/ {print $2}' /proc/meminfo)
    [ "${swap_total:-0}" -gt 0 ] && [ $(( (swap_total - swap_free) * 2 )) -gt "$swap_total" ] &&
        out WARN Performance swap "over half of swap in use ($(( (swap_total - swap_free) / 1024 )) MiB): jobs are short of memory"
    local zombies
    zombies=$(ps -eo stat= | grep -c '^Z')
    [ "$zombies" -gt 20 ] && out WARN Performance processes-zombie "$zombies zombie processes"
    local long
    long=$(ps -eo user=,etimes=,pcpu=,comm= 2>/dev/null | awk '$2 > 2592000 && $3 > 50 {printf "%s:%s(%dd) ", $1, $4, $2/86400}' | head -c 300)
    [ -n "$long" ] && out INFO Performance processes-long "busy processes running for over 30 days: $long"
    systemctl is-active ksmtuned >/dev/null 2>&1 && out INFO Performance ksm "ksmtuned is running (wastes CPU on compute nodes: systemctl disable --now ksmtuned ksm)"
    if have journalctl; then
        local oom
        oom=$(journalctl -k --since "7 days ago" --no-pager 2>/dev/null | grep -ci 'out of memory')
        [ "${oom:-0}" -gt 0 ] && out WARN Performance memory-oom "$oom out-of-memory kills in the last 7 days"
    fi
}

check_gpu() {
    local cards
    cards=$(lspci 2>/dev/null | grep -iE 'vga|3d controller' | grep -i nvidia | sed 's/.*: //; s/NVIDIA Corporation //; s/ (rev [0-9a-f]*)//' | sort | uniq -c | sed 's/^ *//' | paste -sd ';' - | sed 's/;/; /g')
    [ -z "$cards" ] && return
    if ! have nvidia-smi; then
        out INFO Hardware gpu "NVIDIA card ($cards) but no NVIDIA driver installed (fine for a display-only card)"
    elif nvidia-smi -L >/dev/null 2>&1; then
        out OK Hardware gpu "NVIDIA driver working: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | sort | uniq -c | sed 's/^ *//; s/,/ driver/' | paste -sd ';' - | sed 's/;/; /g')"
    else
        if [ "$PKG" = apt ]; then
            out WARN Hardware gpu "NVIDIA driver installed but not working ($cards): usually a kernel update without its NVIDIA module (sudo apt full-upgrade, then reboot)"
        else
            out WARN Hardware gpu "NVIDIA driver installed but not working ($cards): rebuild or reinstall the driver for kernel $(uname -r)"
        fi
    fi
}

check_os
check_updates
check_services
check_disks
check_backups
check_group_setup
check_versions
check_world_writable
check_ownership
check_firewall
check_accounts
check_my_ssh
check_performance
check_gpu
exit 0
