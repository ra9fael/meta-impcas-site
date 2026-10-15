SUMMARY = "Mount the BOOT partition read-only at /boot"
DESCRIPTION = "Mount the FAT BOOT partition (filesystem label BOOT) read-only \
at /boot, so site configuration (network settings, the IOC machine layer, FPGA \
bitstreams) placed on the SD card's first partition is visible to the running \
system. Nothing writes /boot at runtime -- the machine's own data lives on the \
journaling ext4 rootfs -- which is what keeps a power cut from leaving the FAT \
dirty and the kernel taking the partition away mid-boot. Editing the \
configuration on the target goes through the boot-rw and boot-ro commands, \
which open a timed write window and hand it to a timer that closes it by \
itself, so the partition does not depend on anyone remembering to put it back. \
boot-check reports what the FAT looks like: it reads the volume with fsck.vfat \
-n, which cannot write, and prints how to repair the partition without \
repairing it, because repairing means unmounting the card the configuration is \
read from and that is a decision for whoever is standing there."
HOMEPAGE = "https://github.com/ra9fael/meta-impcas-util"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://bootmount.sh \
           file://bootmount.service \
           file://boot-rw \
           file://boot-ro \
           file://boot-check \
           file://boot-ro.service \
           file://boot-ro.timer \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "bootmount.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# boot-ro.service and boot-ro.timer are installed but deliberately not listed
# above: they have no [Install] section because a write window must not survive
# a reboot -- boot-rw starts the timer and both boot-ro and the auto-close path
# stop it, so the pair only ever runs while /boot is writable.
do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${WORKDIR}/bootmount.sh ${D}${sbindir}/bootmount.sh
    install -m 0755 ${WORKDIR}/boot-rw ${D}${sbindir}/boot-rw
    install -m 0755 ${WORKDIR}/boot-ro ${D}${sbindir}/boot-ro
    install -m 0755 ${WORKDIR}/boot-check ${D}${sbindir}/boot-check
    install -m 0644 ${WORKDIR}/bootmount.service ${D}${systemd_system_unitdir}/bootmount.service
    install -m 0644 ${WORKDIR}/boot-ro.service ${D}${systemd_system_unitdir}/boot-ro.service
    install -m 0644 ${WORKDIR}/boot-ro.timer ${D}${systemd_system_unitdir}/boot-ro.timer
    sed -i s,@SBINDIR@,${sbindir},g ${D}${systemd_system_unitdir}/bootmount.service \
        ${D}${systemd_system_unitdir}/boot-ro.service ${D}${sbindir}/boot-rw \
        ${D}${sbindir}/boot-ro ${D}${sbindir}/boot-check
}

FILES:${PN} = "${sbindir}/bootmount.sh \
               ${sbindir}/boot-rw \
               ${sbindir}/boot-ro \
               ${sbindir}/boot-check \
               ${systemd_system_unitdir}/bootmount.service \
               ${systemd_system_unitdir}/boot-ro.service \
               ${systemd_system_unitdir}/boot-ro.timer \
"

# mountpoint and findmnt do the mount bookkeeping; fsck.vfat is what boot-check
# and the boot-rw preflight read the FAT with. The check fails open -- a missing
# fsck.vfat costs one warning line, not the card -- but the feature ships
# expecting the tool, and dosfstools is already in this image.
RDEPENDS:${PN} = "util-linux-mountpoint util-linux-findmnt dosfstools"
