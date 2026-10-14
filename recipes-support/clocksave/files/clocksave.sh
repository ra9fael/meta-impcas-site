#!/bin/sh
# SPDX-FileCopyrightText: 2026 IMPCAS
#
# SPDX-License-Identifier: MIT

# Persist the system clock on boards without an RTC, Debian fake-hwclock
# style: "restore" steps the clock to the last saved value early at boot and
# "save" records the current time under /var/lib/clocksave. Both only ever
# move the recorded time FORWARD, so a board booting into the kernel's default
# time (no RTC, NTP not yet reachable) can neither regress the clock nor
# overwrite a good timestamp with a stale one.
#
# The file lives on the journaling ext4 rootfs, not on the BOOT partition: a
# timer-driven write to the FAT is exactly what a power cut used to turn into
# a dirty volume and a read-only /boot, and the clock is the one value here
# whose loss is cheap -- forward-only saves plus NTP make a missing file a
# stale clock for one boot, not lost data. PID1 has the root mounted rw before
# sysinit.target, so the restore and every save path read and write it for
# free.

set -e

CLOCK_FILE=/var/lib/clocksave/clock.save
# Nothing earlier than 2025-01-01 counts as a real time here: the kernel
# default on a no-RTC board is far in the past, never record it.
MIN_EPOCH=1735689600

read_saved() {
    saved=""
    if [ -r "$CLOCK_FILE" ]; then
        saved=$(head -n 1 "$CLOCK_FILE" 2>/dev/null || true)
    fi
    case "$saved" in
        ''|*[!0-9]*) saved=0 ;;
    esac
    echo "$saved"
}

save() {
    now=$(date +%s)
    [ "$now" -ge "$MIN_EPOCH" ] || { echo "clocksave: clock below $MIN_EPOCH, not saving"; exit 0; }
    [ "$now" -gt "$(read_saved)" ] || exit 0
    # First save on a fresh rootfs creates the directory.
    mkdir -p "${CLOCK_FILE%/*}"
    printf '%s\n' "$now" > "$CLOCK_FILE.tmp"
    mv "$CLOCK_FILE.tmp" "$CLOCK_FILE"
    sync
    echo "clocksave: saved $(date)"
}

restore() {
    saved=$(read_saved)
    [ "$saved" -gt "$(date +%s)" ] || exit 0
    date -s "@$saved" >/dev/null
    echo "clocksave: restored $(date) from $CLOCK_FILE"
}

case "${1:-}" in
    save) save ;;
    restore) restore ;;
    *) echo "usage: $0 {save|restore}" >&2; exit 1 ;;
esac
