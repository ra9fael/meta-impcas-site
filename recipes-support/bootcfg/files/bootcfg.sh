#!/bin/sh
# SPDX-FileCopyrightText: 2026 IMPCAS
#
# SPDX-License-Identifier: MIT

# Configure networking and NTP from /boot/machine.cfg (a plain KEY=value file on
# the writable BOOT partition, edited per machine before first boot). The
# rootfs is read-only and identical on every machine, so the generated
# configuration goes to /run, which systemd-networkd and systemd-timesyncd
# read like any other configuration directory.
#
# Keys:
#   INTERFACE   interface name to match (default eth0)
#   MACADDRESS  hardware address to set on the interface
#   IPADDRESS   static IPv4 address
#   NETMASK     dotted netmask (or use PREFIXLEN directly)
#   PREFIXLEN   prefix length, takes precedence over NETMASK
#   GATEWAY     default gateway
#   DNS         space-separated DNS servers
#   NTP         space-separated NTP servers
#   HOSTNAME    machine host name (written to /etc/hostname and applied)
#
# With no /boot/machine.cfg the service exits and the built-in networkd
# configuration applies unchanged.

set -e

CFG=/boot/machine.cfg
NETWORK_DIR=/run/systemd/network
TIMESYNC_CONF=/run/systemd/timesyncd.conf.d/bootcfg.conf
NETWORK_FILE=$NETWORK_DIR/80-bootcfg.network
HOSTNAME_FILE=/etc/hostname

[ -r "$CFG" ] || { echo "bootcfg: no $CFG, keeping built-in network config"; exit 0; }

# Only plain KEY=value lines with a safe value charset are accepted; the file
# is sourced, so anything that could execute must be rejected up front.
if grep -Evq '^[[:space:]]*(#|$)|^[A-Za-z_][A-Za-z0-9_]*="?[A-Za-z0-9_.:/ -]*"?[[:space:]]*$' "$CFG"; then
    echo "bootcfg: $CFG contains unsupported lines, ignoring it" >&2
    exit 1
fi

. "$CFG"

INTERFACE=${INTERFACE:-eth0}

# NETMASK (e.g. 255.255.255.0) -> prefix length, plain POSIX arithmetic.
mask_to_prefix() {
    prefix=0
    for octet in $(echo "$1" | tr '.' ' '); do
        while [ "$octet" -ne 0 ]; do
            prefix=$((prefix + octet % 2))
            octet=$((octet / 2))
        done
    done
    echo "$prefix"
}

if [ -z "$PREFIXLEN" ] && [ -n "$NETMASK" ]; then
    PREFIXLEN=$(mask_to_prefix "$NETMASK")
fi

mkdir -p "$NETWORK_DIR" "$(dirname "$TIMESYNC_CONF")"

{
    echo "[Match]"
    echo "Name=$INTERFACE"
    echo ""
    echo "[Link]"
    [ -n "$MACADDRESS" ] && echo "MACAddress=$MACADDRESS"
    echo ""
    echo "[Network]"
    if [ -n "$IPADDRESS" ]; then
        if [ -n "$PREFIXLEN" ]; then
            echo "Address=$IPADDRESS/$PREFIXLEN"
        else
            echo "Address=$IPADDRESS"
        fi
    fi
    [ -n "$GATEWAY" ] && echo "Gateway=$GATEWAY"
    for server in $DNS; do
        echo "DNS=$server"
    done
} > "$NETWORK_FILE"

if [ -n "$NTP" ]; then
    {
        echo "[Time]"
        echo "NTP=$NTP"
    } > "$TIMESYNC_CONF"
fi

if [ -n "$HOSTNAME" ]; then
    # The rootfs is mounted rw at runtime, so /etc/hostname is writable and
    # the name survives reboots without the bootcfg service.
    echo "$HOSTNAME" > "$HOSTNAME_FILE"
    hostname "$HOSTNAME"
fi

echo "bootcfg: wrote $NETWORK_FILE${NTP:+ and $TIMESYNC_CONF}${HOSTNAME:+, hostname $HOSTNAME} from $CFG"
