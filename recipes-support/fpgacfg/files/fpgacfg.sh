#!/bin/sh
# SPDX-FileCopyrightText: 2026 IMPCAS
#
# SPDX-License-Identifier: MIT

# Configure the PL from the BOOT partition. /boot/fpga is a pool: any number
# of *.bin files (Xilinx bin format, including *.bit.bin files converted from
# raw *.bit with fpgautil -B offline), exactly one of
# which is selected by the KEY=value file /boot/fpga/active.conf:
#
#     BITSTREAM=blm_prod.bit.bin
#
# Without arguments (the systemd service) the selected bitstream is loaded
# through Xilinx fpgautil. With a file-name argument the given pool file is
# loaded immediately, for switching at runtime without a reboot -- note that
# whatever application mapped the PL keeps stale register mappings and has to
# be restarted afterwards.
#
# A deployment that configures the PL from BOOT.BIN through the FSBL needs no
# runtime loading: with no /boot/fpga directory (or an empty pool) this
# script is a no-op. An ambiguous pool -- files present but no active.conf,
# or a selection that does not exist -- is an error listing the candidates:
# loading a wrong bitstream silently would be far worse than failing to
# configure the PL at all.

set -e

FPGA_DIR=/boot/fpga
ACTIVE="$FPGA_DIR/active.conf"

pool_files() {
    for f in "$FPGA_DIR"/*.bin; do
        [ -f "$f" ] && echo "$f"
    done
}

load() {
    echo "fpgacfg: loading $1"
    fpgautil -b "$1"
}

if [ -n "$1" ]; then
    # Manual mode: exactly one plain file name inside the pool.
    case "$1" in
        */*|.*|"")
            echo "fpgacfg: '$1' is not a plain file name under $FPGA_DIR" >&2
            exit 1
            ;;
    esac
    [ -f "$FPGA_DIR/$1" ] || {
        echo "fpgacfg: no such bitstream: $FPGA_DIR/$1" >&2
        exit 1
    }
    load "$FPGA_DIR/$1"
    echo "fpgacfg: done -- restart any application that mapped the PL."
    exit 0
fi

# Boot mode.
if [ ! -d "$FPGA_DIR" ] || [ -z "$(pool_files)" ]; then
    echo "fpgacfg: no bitstream pool under $FPGA_DIR, nothing to load"
    exit 0
fi

if [ ! -r "$ACTIVE" ]; then
    echo "fpgacfg: bitstreams present but $ACTIVE is missing, refusing to guess" >&2
    echo "fpgacfg: available bitstreams:" >&2
    pool_files | sed 's|^|fpgacfg:   |' >&2
    exit 1
fi

# The file is sourced, so only the one known KEY with a safe value charset
# is accepted.
if grep -Evq '^[[:space:]]*(#|$)|^BITSTREAM="?[A-Za-z0-9._-]+"?[[:space:]]*$' "$ACTIVE"; then
    echo "fpgacfg: $ACTIVE contains unsupported lines, ignoring it" >&2
    exit 1
fi

. "$ACTIVE"

if [ -z "$BITSTREAM" ] || [ ! -f "$FPGA_DIR/$BITSTREAM" ]; then
    echo "fpgacfg: BITSTREAM='$BITSTREAM' not found in $FPGA_DIR" >&2
    echo "fpgacfg: available bitstreams:" >&2
    pool_files | sed 's|^|fpgacfg:   |' >&2
    exit 1
fi

load "$FPGA_DIR/$BITSTREAM"
