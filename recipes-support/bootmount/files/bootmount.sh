#!/bin/sh
# SPDX-FileCopyrightText: 2026 IMPCAS
#
# SPDX-License-Identifier: MIT

# Mount the BOOT partition at /boot. The partition is identified by its
# filesystem label (format-sd.sh labels it BOOT), never by a device name:
# mmcblk0/mmcblk1 numbering differs between boards and images.
#
# The rootfs ships its own /boot directory with copies of the boot files;
# once this mount succeeds those copies are shadowed, which is harmless --
# U-Boot reads the partition directly, not through the rootfs (the image
# build deletes them anyway).
#
# vfat has no permission bits of its own: everything would show up owned by
# root and read-only for everyone else. umask=000 makes the whole partition
# writable by any local user, which is the point of the site-config scheme --
# the operator edits machine.cfg, envPaths and bitstreams without sudo. On an
# appliance whose IOC already runs as root this grants nothing new, and
# anyone with the SD card in a PC has full access regardless. noatime keeps
# read access from dirtying the FAT.

set -e

mkdir -p /boot

if mountpoint -q /boot; then
    echo "bootmount: /boot already mounted"
    exit 0
fi

if ! mount -o umask=000,noatime LABEL=BOOT /boot; then
    echo "bootmount: no filesystem labelled BOOT found" >&2
    exit 1
fi

echo "bootmount: mounted $(findmnt -n -o SOURCE /boot) at /boot (world-writable)"
