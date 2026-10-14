#!/bin/sh
# SPDX-FileCopyrightText: 2026 IMPCAS
#
# SPDX-License-Identifier: MIT

# Mount the BOOT partition at /boot, read-only. The partition is identified by
# its filesystem label (format-sd.sh labels it BOOT), never by a device name:
# mmcblk0/mmcblk1 numbering differs between boards and images.
#
# The rootfs ships its own /boot directory with copies of the boot files;
# once this mount succeeds those copies are shadowed, which is harmless --
# U-Boot reads the partition directly, not through the rootfs (the image
# build deletes them anyway).
#
# Read-only is the design, not an oversight. The BOOT partition is the
# deployer's medium: network settings, the IOC machine layer, the bitstream
# pool -- everything the boot chain reads off it, and everything edited
# offline with the card in a PC. The machine's own data (autosave saves, ADC
# calibration, the saved clock) lives on the journaling ext4 rootfs, so no
# running service ever writes /boot, and a power cut can no longer leave the
# FAT dirty and take the partition away from bootcfg, fpgacfg and ioc-start
# mid-boot. Windows sets the FAT dirty bit when it mounts a volume and clears
# it on a safe eject: a card pulled without one still mounts here, because
# nothing is left to write to it -- the kernel may print one warning line
# about the dirty volume, and a manual `fsck.vfat -a` with the card in a PC is
# the repair, never a boot-time truncation of files no one noticed breaking.
#
# To edit the configuration from the running target, open the window by hand
# and close it before power is lost:
#
#     mount -o remount,rw /boot
#     ... edit ... ; sync
#     mount -o remount,ro /boot
#
# Anything written inside that window goes to a filesystem with no journal
# and no atomicity, so keep it short and always return it to ro: what lives
# on the card is configuration the build can project again, never the only
# copy of machine data.

set -e

mkdir -p /boot

if mountpoint -q /boot; then
    echo "bootmount: /boot already mounted"
    exit 0
fi

if ! mount -o ro LABEL=BOOT /boot; then
    echo "bootmount: no filesystem labelled BOOT found" >&2
    exit 1
fi

echo "bootmount: mounted $(findmnt -n -o SOURCE /boot) at /boot (read-only)"
