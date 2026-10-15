#!/bin/sh
# SPDX-FileCopyrightText: 2026 IMPCAS
#
# SPDX-License-Identifier: MIT

# Mount the BOOT partition (label BOOT) at /boot read-only, and run the write
# window that edits it.
#
# The partition is identified by its filesystem label (format-sd.sh labels it
# BOOT), never by a device name: mmcblk0/mmcblk1 numbering differs between
# boards and images.
#
# The rootfs ships its own /boot directory with copies of the boot files; once
# this mount succeeds those copies are shadowed, which is harmless -- U-Boot
# reads the partition directly, not through the rootfs (the image build deletes
# them anyway).
#
# Read-only is the design, not an oversight. The BOOT partition is the
# deployer's medium: network settings, the IOC machine layer, the bitstream
# pool -- everything the boot chain reads off it, and everything edited offline
# with the card in a PC. The machine's own data (autosave saves, ADC
# calibration, the saved clock) lives on the journaling ext4 rootfs, so no
# running service ever writes /boot, and a power cut can no longer leave the FAT
# dirty and take the partition away from bootcfg, fpgacfg and ioc-start
# mid-boot. Windows sets the FAT dirty bit when it mounts a volume and clears it
# on a safe eject: a card pulled without one still mounts here, because nothing
# is left to write to it -- the kernel prints one warning line about the dirty
# volume and mounts it anyway, which is why boot-rw asks before it opens the
# window instead of trusting the mount to complain.
#
# The subcommands:
#
#   mount    bootmount.service: mount read-only, and warn once if the last write
#            window was never closed
#   open     boot-rw: check the FAT, make /boot writable, start the lease
#   close    boot-ro: put it back now
#   auto     boot-ro.timer, every minute while a window is open: close it when
#            the lease runs out, retry while something is still writing
#   check    boot-check: report what the FAT looks like and how to repair it,
#            and never repair it
#
# The guards on the window are the kernel's own rather than ours.
# `remount,rw` fails outright once the FAT has been taken read-only after an
# error, so the window cannot be opened on a volume that has already failed
# under this machine; `remount,ro` fails with EBUSY while a process holds a file
# open for writing, so a lease expiring in the middle of an edit costs a refused
# close and a retry, never a half-written file. BOOT_RW_WINDOW=<seconds> before
# boot-rw sizes the lease; running boot-rw again extends it.
#
# The record of each window is kept on the journaling ext4 rootfs, never on the
# FAT it describes: it says whether the last window was closed, which is the one
# thing a machine can still tell after the power is lost.

set -e

MOUNT=/boot
STATE=/var/lib/bootmount/window
SPOKEN=/run/bootmount-window.expired
LABEL_DEV=/dev/disk/by-label/BOOT
LEASE=600
TIMER=boot-ro.timer

stamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

mounted() {
    mountpoint -q "$MOUNT"
}

# Written as an "is it writable" test rather than the reverse: a mount the
# tools cannot describe is treated as read-only, which is the side that costs
# nothing to be wrong on.
is_rw() {
    case ",$(findmnt -n -o OPTIONS -- "$MOUNT")," in
        *,rw,*) return 0 ;;
    esac
    return 1
}

key() {
    sed -n "s/^$1=//p" "$STATE" 2>/dev/null | head -n 1
}

record() {
    mkdir -p "${STATE%/*}"
    printf 'state=%s\nat=%s\ndeadline=%s\n' "$1" "$(stamp)" "$2" > "$STATE.tmp"
    mv -f "$STATE.tmp" "$STATE"
    # The record only earns its keep if it survives the power cut it is
    # recording, so it is on the platter before the window is reported open.
    sync
}

arm() {
    # restart covers both cases at once: started when no window was open, and
    # re-armed from this moment when one already was (that is how boot-rw twice
    # extends a lease).
    if systemctl restart "$TIMER"; then
        return 0
    fi
    echo "boot-rw: $TIMER would not start, so nothing can close the window" >&2
    echo "         automatically." >&2
    return 1
}

stop_timer() {
    systemctl stop "$TIMER" 2>/dev/null || true
    rm -f "$SPOKEN"
}

# Name whatever is holding the volume busy instead of telling the operator to
# go and look: fuser ships with this image's debug packagegroup, and where it
# does not, the line is simply absent.
busy_by() {
    command -v fuser >/dev/null 2>&1 || return 0
    # fuser pads its list with its own spacing; echo without quotes collapses it.
    pids=$(echo $(fuser -m "$MOUNT" 2>/dev/null || true))
    if [ -n "$pids" ]; then
        echo "         still held open by PID(s): $pids" >&2
    fi
}

# The block device of the volume: the mount's own source while /boot is
# mounted, the label symlink while it is not -- an unmounted card is exactly
# when looking at it is worth something.
volume() {
    dev=""
    if mounted; then
        dev=$(findmnt -n -o SOURCE -- "$MOUNT" 2>/dev/null | head -n 1)
    fi
    if [ -z "$dev" ] && [ -e "$LABEL_DEV" ]; then
        dev=$LABEL_DEV
    fi
    [ -n "$dev" ] || return 1
    printf '%s\n' "$dev"
}

# fsck.vfat -n is a check that cannot write: it opens the volume read-only,
# leaves the dirty bit set exactly as it found it (verified: two runs over the
# same damaged volume print the same thing, and the image's sha256 is
# unchanged), and reports what it would have changed. That is what makes it
# safe to run against a partition that is mounted, and safe to run on a card
# this machine cannot afford to make worse. Without -n the default action is
# -r, an interactive repair, so -n is not a style choice.
#
# The exit code carries no information: a broken FAT chain exits 1, a
# boot-sector whose backup copy disagrees exits 1 too, a volume that -a
# really did rewrite exits 1 as well, and an unreadable device exits 6 -- so
# the verdict comes from the finding lines. Anything that is not a
# known-cosmetic complaint counts as damage, because being wrong in that
# direction costs one refused window and a second thought, while being wrong
# the other way means editing a filesystem that was already losing files.
damaging_re='Dirty bit is set|not properly unmounted|FATs differ|out of range|Reclaimed|Bad sector|bad cluster|cross-linked|Duplicate|cluster chain|truncat|salvage|Deleted file|dead cluster'
cosmetic_re='^fsck\.fat |^Leaving filesystem |^Checking |mostly harmless|between boot sector and its backup|Not automatically fixing|Auto-correcting|Automatically removing dirty bit|Free cluster summary|FSINFO|uninitialized|^ *Offset [0-9]|^ *[0-9a-fx/]+:[0-9a-fx/]+|^ *Using (first|second) FAT|files, [0-9]+/[0-9]+ clusters|^ *$'

# The repair sequence, printed and never run. Repairing here would mean
# unmounting the partition this machine's configuration is read from, stopping
# the IOCs that started from it, and deciding all that inside a command whose
# only job was to open a write window -- and the card holds nothing a
# re-deploy cannot project again.
advice() {
    who=$1
    echo "$who: repair it yourself; this command will not:" >&2
    echo "         boot-ro" >&2
    echo "                  close the write window first" >&2
    echo "         systemctl stop epics-ioc@<instance>" >&2
    echo "                  every IOC whose machine layer is read off the card" >&2
    echo "         umount $MOUNT" >&2
    echo "         fsck.vfat -l -r $LABEL_DEV" >&2
    echo "                  -l says what it would do, -r asks before each change" >&2
    echo "         systemctl restart bootmount.service" >&2
    echo "                  put it back read-only" >&2
    echo "         systemctl start epics-ioc@<instance>" >&2
    echo "$who: or take the card out and 'fsck.vfat -a' it in a PC, or re-deploy" >&2
    echo "         it with scripts/inflate-sd.sh: what the card holds is" >&2
    echo "         configuration the build can project again, never the only copy" >&2
    echo "         of machine data." >&2
}

# Reads the volume and reports it. Sets FAT to clean, cosmetic, damaged or
# unreadable; damaged and unreadable are written to stderr, because they are
# the two answers that stop something.
read_fat() {
    who=$1
    FAT=unreadable
    if ! command -v fsck.vfat >/dev/null 2>&1; then
        echo "$who: no fsck.vfat on this image, so the FAT could not be read." >&2
        return 0
    fi
    if ! dev=$(volume); then
        echo "$who: no filesystem labelled BOOT to check." >&2
        return 0
    fi
    # The exit code is not evidence of anything here -- -n exits 1 precisely
    # when it has found something to say -- so only a device that could not be
    # opened at all counts as unreadable.
    out=$(fsck.vfat -n "$dev" 2>&1) || true
    if printf '%s\n' "$out" | grep -qiE '^open: |permission denied|no such file|unable to open|cannot open'; then
        echo "$who: $dev cannot be read:" >&2
        printf '%s\n' "$out" | sed 's/^/         /' >&2
        return 0
    fi

    if printf '%s\n' "$out" | grep -qE "$damaging_re"; then
        FAT=damaged
        echo "$who: $dev is damaged:" >&2
        printf '%s\n' "$out" | grep -vE "$cosmetic_re" | sed 's/^/         /' >&2
        advice "$who"
        return 0
    fi
    left=$(printf '%s\n' "$out" | grep -vE "$cosmetic_re" || true)
    if [ -n "$left" ]; then
        FAT=damaged
        echo "$who: $dev says something this pattern does not know:" >&2
        printf '%s\n' "$left" | sed 's/^/         /' >&2
        advice "$who"
        return 0
    fi
    if printf '%s\n' "$out" | grep -qE 'mostly harmless|Auto-correcting|Free cluster summary|FSINFO'; then
        FAT=cosmetic
        echo "$who: $dev needs no repair, but its bookkeeping is stale:" >&2
        printf '%s\n' "$out" | grep -E 'mostly harmless|Auto-correcting|Free cluster summary|FSINFO|boot sector and its backup' \
            | head -n 2 | sed 's/^/         /' >&2
        return 0
    fi
    FAT=clean
    return 0
}

mount_boot() {
    mkdir -p "$MOUNT"

    if mounted; then
        echo "bootmount: $MOUNT already mounted"
        exit 0
    fi

    if ! mount -o ro LABEL=BOOT "$MOUNT"; then
        echo "bootmount: no filesystem labelled BOOT found" >&2
        exit 1
    fi

    echo "bootmount: mounted $(findmnt -n -o SOURCE "$MOUNT") at $MOUNT (read-only)"

    # Tripwire. boot-rw records an open window on the journaling rootfs and
    # boot-ro -- or its timer -- records the close, so a record still open here
    # means the last window ended without one: a power cut inside it, which is
    # the failure this read-only mount exists to survive. Say it out loud, then
    # acknowledge the record so the warning costs one boot rather than every
    # boot until somebody opens and closes a window properly; the timestamp of
    # the window that was never closed stays in the file as the evidence.
    if [ -r "$STATE" ] && grep -q '^state=open$' "$STATE"; then
        echo "bootmount: WARNING the $MOUNT write window opened $(sed -n 's/^at=//p' "$STATE" | head -n 1)" >&2
        echo "bootmount: was never closed, so the power was probably lost inside" >&2
        echo "bootmount: it. Run boot-check to see what the FAT looks like now." >&2
        echo "bootmount: The card holds configuration only; the build can project it again." >&2
        sed -i 's/^state=open$/state=warned/' "$STATE" 2>/dev/null || true
    fi
}

open_window() {
    if ! mounted; then
        echo "boot-rw: $MOUNT is not mounted -- bootmount.service found no" >&2
        echo "         filesystem labelled BOOT on this card." >&2
        exit 1
    fi

    # Before the window, not after: while the volume is read-only nothing of
    # ours is sitting in the page cache, so this is the one moment the check
    # sees the card as the boot chain will see it.
    read_fat boot-rw
    case "$FAT" in
        damaged)
            if [ -z "${BOOT_RW_FORCE:-}" ]; then
                echo "boot-rw: $MOUNT stays read-only. BOOT_RW_FORCE=1 opens it anyway." >&2
                exit 1
            fi
            echo "boot-rw: BOOT_RW_FORCE is set, opening a damaged FAT." >&2 ;;
        unreadable)
            # Checking is a favour, not a gate: an image without dosfstools
            # must not lock anybody out of their own card.
            echo "boot-rw: opening the window with the FAT unchecked." >&2 ;;
    esac

    if is_rw; then
        echo "boot-rw: $MOUNT was already writable; the lease restarts from now."
    elif ! mount -o remount,rw "$MOUNT"; then
        echo "boot-rw: the kernel will not let $MOUNT be written: the FAT was" >&2
        echo "         taken read-only after an error. Do not force it -- repair" >&2
        echo "         it (boot-check prints the sequence) or re-deploy the card" >&2
        echo "         with scripts/inflate-sd.sh." >&2
        exit 1
    fi

    lease=${BOOT_RW_WINDOW:-$LEASE}
    case "$lease" in
        ''|*[!0-9]*) lease=$LEASE ;;
    esac
    # The deadline is a wall-clock epoch, so an NTP step inside a window moves
    # the close time with it; both directions are harmless here, since the card
    # holds configuration the build can project again.
    until=$(( $(date +%s) + lease ))

    record open "$until"
    if ! arm; then
        # No lease, no write access: leaving /boot writable on the strength of
        # the operator remembering to run boot-ro is exactly what this is not.
        sync
        if mount -o remount,ro "$MOUNT"; then
            echo "boot-rw: $MOUNT is read-only, nothing was changed." >&2
        else
            echo "boot-rw: $MOUNT IS STILL WRITABLE -- run boot-ro before power" >&2
            echo "         is lost." >&2
        fi
        record closed -
        exit 1
    fi

    echo "boot-rw: $MOUNT is writable for the next ${lease}s."
    echo "         Configuration only: the autosave saves, the ADC calibration"
    echo "         and clock.save live on the rootfs and never need this window."
    echo "         $MOUNT goes back to read-only by itself, or now with boot-ro."
}

close_window() {
    if ! mounted; then
        stop_timer
        record closed -
        echo "boot-ro: $MOUNT is not mounted."
        exit 0
    fi
    if ! is_rw; then
        stop_timer
        record closed -
        echo "boot-ro: $MOUNT is already read-only."
        exit 0
    fi
    # sync first: everything the window wrote has to be on the card before the
    # volume stops accepting writes.
    sync
    if ! mount -o remount,ro "$MOUNT"; then
        # The timer is deliberately left running: it is what closes the volume
        # once the writer that is blocking this goes away.
        echo "boot-ro: refused -- a process still holds a file on $MOUNT open" >&2
        echo "         for writing (the kernel will not make a busy FAT" >&2
        echo "         read-only). If the window was opened with boot-rw its" >&2
        echo "         timer closes it on its own when that writer goes away." >&2
        busy_by
        exit 1
    fi
    stop_timer
    record closed -
    echo "boot-ro: $MOUNT is read-only again."
}

auto() {
    # The timer's own view of the window: quiet unless it changes something,
    # because it runs once a minute for as long as a window is open.
    if ! mounted; then
        stop_timer
        exit 0
    fi
    if ! is_rw; then
        # Someone closed the window outside these commands (a hand-typed
        # remount, an unmount, the FAT erroring out): the lease is spent.
        stop_timer
        if [ "$(key state)" = "open" ]; then
            record closed -
            echo "boot-ro: $MOUNT is already read-only; window record cleared."
        fi
        exit 0
    fi

    deadline=$(key deadline)
    case "$deadline" in
        ''|*[!0-9]*) deadline=0 ;;
    esac
    if [ "$(date +%s)" -lt "$deadline" ]; then
        exit 0
    fi

    sync
    if mount -o remount,ro "$MOUNT" 2>/dev/null; then
        stop_timer
        record closed -
        echo "boot-ro: the write window expired; $MOUNT is read-only again."
        exit 0
    fi
    # Busy is normal: the timer polls every minute and the FAT stays writable
    # until the edit in progress can end. Saying so once per window is enough --
    # a writer that never lets go would otherwise fill the journal every minute.
    if [ ! -e "$SPOKEN" ]; then
        : > "$SPOKEN"
        echo "boot-ro: the write window expired but $MOUNT still holds" >&2
        echo "boot-ro: a writer; closing it as soon as that ends." >&2
        busy_by
    fi
}

check_command() {
    read_fat boot-check
    case "$FAT" in
        clean)
            echo "boot-check: $dev is consistent."
            exit 0 ;;
        cosmetic)
            echo "boot-check: $dev is sound; only its own counters are stale."
            exit 0 ;;
        damaged)
            exit 1 ;;
        *)
            exit 3 ;;
    esac
}

case "${1:-}" in
    mount) mount_boot ;;
    open) open_window ;;
    close) close_window ;;
    auto) auto ;;
    check) check_command ;;
    *) echo "usage: $0 {mount|open|close|auto|check}" >&2; exit 1 ;;
esac
