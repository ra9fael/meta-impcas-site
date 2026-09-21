#!/bin/sh
# SPDX-FileCopyrightText: 2026 IMPCAS
#
# SPDX-License-Identifier: MIT

# Configure the PL from the BOOT partition. /boot/fpga is a pool: any number
# of *.bin files (Xilinx bin format, including *.bit.bin files converted from
# raw *.bit with fpgautil -B offline), from which one is selected by the
# KEY=value file /boot/fpga/active.conf:
#
#     BITSTREAM=blm_prod.bit.bin   # exact pool file name
#     BITSTREAM=*.bin              # or a glob pattern over the pool
#
# A value containing * or ? is a glob matched against the pool files; if it
# matches several, the newest one by modification time wins (the usual
# default BITSTREAM=*.bin means "load the bitstream swept last"). A value
# without wildcards must name a pool file exactly. Matching is
# case-insensitive -- the BOOT partition is FAT32, where file names are
# case-insensitive too -- and only *.bin files (any case) can ever match, so
# the pattern cannot pick up active.conf itself.
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
    for f in "$FPGA_DIR"/*; do
        case $f in
            *.[bB][iI][nN]) [ -f "$f" ] && echo "$f" ;;
        esac
    done
}

# Case-insensitive glob match: uppercase both sides and compare with an
# anchored ERE derived from the glob. The BITSTREAM charset restricts the
# glob syntax to * ? and literal '.', of which only '.' is a regex
# metacharacter, so the translation stays trivial.
ci_glob() {
    pat=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' |
          sed -e 's/\./\\./g' -e 's/\*/.*/g' -e 's/\?/./g')
    name=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')
    printf '%s\n' "$name" | grep -Eq "^${pat}\$"
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
# is accepted (* and ? make the value a glob; - is last in the class so it
# stays literal).
if grep -Evq '^[[:space:]]*(#|$)|^BITSTREAM="?[A-Za-z0-9._*?-]+"?[[:space:]]*$' "$ACTIVE"; then
    echo "fpgacfg: $ACTIVE contains unsupported lines, ignoring it" >&2
    exit 1
fi

# The config file is the only source of BITSTREAM.
unset BITSTREAM
. "$ACTIVE"

if [ -z "$BITSTREAM" ]; then
    echo "fpgacfg: bitstreams present but $ACTIVE selects none" >&2
    echo "fpgacfg: available bitstreams:" >&2
    pool_files | sed 's|^|fpgacfg:   |' >&2
    exit 1
fi

# Resolve BITSTREAM against the pool: an exact pool file name or a glob
# pattern over it, matched case-insensitively, and only ever against *.bin
# files (any case), so active.conf itself can never match. Several matches
# load the newest file by mtime.
matches=
for f in "$FPGA_DIR"/*; do
    case $f in
        *.[bB][iI][nN])
            [ -f "$f" ] && ci_glob "$BITSTREAM" "${f##*/}" && matches="$matches $f"
            ;;
    esac
done

if [ -z "$matches" ]; then
    echo "fpgacfg: no pool file matches BITSTREAM='$BITSTREAM'" >&2
    echo "fpgacfg: available bitstreams:" >&2
    pool_files | sed 's|^|fpgacfg:   |' >&2
    exit 1
fi

set -- $matches

if [ "$#" -gt 1 ]; then
    newest=$1
    newest_time=$(stat -c %Y "$1")
    for m in "$@"; do
        t=$(stat -c %Y "$m")
        [ "$t" -gt "$newest_time" ] && { newest=$m; newest_time=$t; }
    done
    echo "fpgacfg: $# bitstreams match '$BITSTREAM', loading the newest one"
    set -- "$newest"
fi

load "$1"
