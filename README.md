# meta-impcas-site

Site-configuration systemd services and tools shared across IMPCAS
PetaLinux projects (Yocto scarthgap / PetaLinux 2024.2):

* `bootmount` -- mount the BOOT partition (label `BOOT`) at `/boot`
* `bootcfg` -- machine identity, network and NTP configuration from `/boot/machine.cfg`;
  `NTP=` servers go to the highest-priority time daemon installed (chronyd >
  ntpd > systemd-timesyncd) and the others are configured too but disabled, so
  exactly one daemon adjusts the clock.
* `fpgacfg` -- load the bitstream selected by `/boot/fpga/active.conf` (a pool of
  files; `fpgacfg.sh <name>` switches at runtime)

Board-specific recipes live in each project's `meta-user`; EPICS recipes live
in `meta-impcas-epics`.
