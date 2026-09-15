#!/bin/sh
# SPDX-FileCopyrightText: 2026 IMPCAS
#
# SPDX-License-Identifier: MIT

# Load FPGA bitstreams from the BOOT partition at boot. Every *.bit.bin
# (and, as a fallback, *.bit) file under /boot/fpga is configured through
# Xilinx fpgautil in lexical order -- normally there is exactly one.
#
# Without a /boot/fpga directory the service exits successfully: a
# deployment that configures the PL from BOOT.BIN through the FSBL needs no
# runtime loading and this service is a no-op.

set -e

FPGA_DIR=/boot/fpga
files=""

if [ -d "$FPGA_DIR" ]; then
    for f in "$FPGA_DIR"/*.bit.bin "$FPGA_DIR"/*.bit; do
        [ -f "$f" ] && files="$files $f"
    done
fi

if [ -z "$files" ]; then
    echo "fpgacfg: no bitstream under $FPGA_DIR, nothing to load"
    exit 0
fi

for f in $files; do
    echo "fpgacfg: loading $f"
    fpgautil -b "$f"
done

echo "fpgacfg: all bitstreams loaded"
