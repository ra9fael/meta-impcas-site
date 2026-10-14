SUMMARY = "Mount the BOOT partition read-only at /boot"
DESCRIPTION = "Mount the FAT BOOT partition (filesystem label BOOT) read-only \
at /boot, so site configuration (network settings, the IOC machine layer, FPGA \
bitstreams) placed on the SD card's first partition is visible to the running \
system. Nothing writes /boot at runtime -- the machine's own data lives on the \
journaling ext4 rootfs -- which is what keeps a power cut from leaving the FAT \
dirty and the kernel taking the partition away mid-boot."
HOMEPAGE = "https://github.com/ra9fael/meta-impcas-util"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://bootmount.sh \
           file://bootmount.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "bootmount.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${WORKDIR}/bootmount.sh ${D}${sbindir}/bootmount.sh
    install -m 0644 ${WORKDIR}/bootmount.service ${D}${systemd_system_unitdir}/bootmount.service
    sed -i s,@SBINDIR@,${sbindir},g ${D}${systemd_system_unitdir}/bootmount.service
}

FILES:${PN} = "${sbindir}/bootmount.sh ${systemd_system_unitdir}/bootmount.service"

RDEPENDS:${PN} = "util-linux-mountpoint util-linux-findmnt"
