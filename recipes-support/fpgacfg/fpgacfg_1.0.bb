SUMMARY = "Load FPGA bitstreams from /boot/fpga at boot"
DESCRIPTION = "Configures the PL through Xilinx fpgautil with every \
bitstream found on the writable BOOT partition, so a bitstream can be \
swapped per machine without rebuilding the rootfs. A deployment that \
loads the PL from BOOT.BIN (FSBL) is unaffected: the service no-ops when \
/boot/fpga is absent or empty."
HOMEPAGE = "https://github.com/ra9fael/meta-impcas-util"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://fpgacfg.sh \
           file://fpgacfg.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "fpgacfg.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${WORKDIR}/fpgacfg.sh ${D}${sbindir}/fpgacfg.sh
    install -m 0644 ${WORKDIR}/fpgacfg.service ${D}${systemd_system_unitdir}/fpgacfg.service
    sed -i s,@SBINDIR@,${sbindir},g ${D}${systemd_system_unitdir}/fpgacfg.service
}

FILES:${PN} = "${sbindir}/fpgacfg.sh ${systemd_system_unitdir}/fpgacfg.service"

RDEPENDS:${PN} = "fpga-manager-script"
