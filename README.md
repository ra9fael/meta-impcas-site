# meta-impcas-site

Site-configuration systemd services and tools shared across IMPCAS
PetaLinux projects (Yocto scarthgap / PetaLinux 2024.2):

* `bootmount` -- mount the BOOT partition (label `BOOT`) at `/boot`
* `bootcfg` -- network and NTP configuration from `/boot/net.cfg`
* `fpgacfg` -- load the bitstream selected by `/boot/fpga/active.conf` (a pool of
  files; `fpgacfg.sh <name>` switches at runtime)

Board-specific recipes live in each project's `meta-user`; EPICS recipes live
in `meta-impcas-epics`.
