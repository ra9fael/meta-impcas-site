# meta-impcas-site

Site-configuration systemd services and tools shared across IMPCAS
PetaLinux projects (Yocto scarthgap / PetaLinux 2024.2):

* `bootmount` -- mount the BOOT partition (label `BOOT`) read-only at `/boot`:
  the card is configuration the boot chain reads and a deployer edits offline
  from a PC, and nothing on the running target writes the FAT. An on-target
  edit goes through `boot-rw` / `boot-ro`, which check the FAT, open a timed
  write window and leave `boot-ro.timer` to close it by itself if the operator
  does not (`BOOT_RW_WINDOW=<seconds>` sizes the lease, `BOOT_RW_FORCE=1` opens
  a volume `boot-rw` would rather not). `boot-check` answers the same question
  on its own: it reads the volume with `fsck.vfat -n`, which cannot write, and
  prints how to repair the partition without repairing it. The check means
  something only while `/boot` is read-only: the kernel sets the FAT dirty bit
  itself for the whole life of a read-write mount, so inside a window both
  commands report that marker as the kernel's own bookkeeping rather than as
  damage (`boot-check` exits 4 for "cannot be judged"), and a second `boot-rw`
  extends the lease without re-checking. Whether the last window was closed is
  recorded on the rootfs and warned about at boot if it was not
* `bootcfg` -- machine identity, network and NTP configuration from
  `/boot/machine/machine.cfg`:
  static addressing by default (one or more addresses, per-address `/prefix` override),
  `DHCP=yes` switches to DHCP and ignores the static address keys; `NTP=` servers go
  to the highest-priority time daemon installed (chronyd > ntpd >
  systemd-timesyncd) and the others are configured too but disabled, so
  exactly one daemon adjusts the clock.
* `clocksave` -- persist the clock across reboots on boards without an RTC:
  restores the last saved time from `/var/lib/clocksave/clock.save` in the
  sysinit phase,
  saves at start, at shutdown and on a 5-minute timer; saves only ever move
  the timestamp forward so a stale kernel-default clock cannot regress it.
* `fpgacfg` -- load the bitstream selected by `/boot/fpga/active.conf` (a pool of
  `*.bin` files; the selection is an exact name or a glob pattern, matched
  case-insensitively, several matches load the newest file by mtime;
  `fpgacfg.sh <name>` switches at runtime). Every load that configures the PL
  leaves the credential `/run/fpgacfg.loaded` for PL-mapping services to gate
  on (the empty-pool no-op exits 0 without writing it; a BOOT.BIN-configured
  board declares itself with the marker `/boot/fpga/preconfigured`)

Board-specific recipes live in each project's `meta-user`; EPICS recipes live
in `meta-impcas-epics`.
