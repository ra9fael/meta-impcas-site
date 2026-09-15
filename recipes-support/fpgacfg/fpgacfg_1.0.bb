SUMMARY = "Load the selected FPGA bitstream from /boot/fpga at boot"
DESCRIPTION = "Configures the PL through Xilinx fpgautil with the bitstream \
selected by /boot/fpga/active.conf out of a pool of bitstream files on the \
writable BOOT partition, so a bitstream can be swapped per machine without \
rebuilding the rootfs. The script also accepts a file-name argument to load \
a pool file at runtime. A deployment that loads the PL from BOOT.BIN (FSBL) \
is unaffected: the service no-ops when /boot/fpga is absent or empty, and \
refuses to guess when bitstreams are present but ambiguous."
HOMEPAGE = "https://github.com/ra9fael/meta-impcas-site"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://fpgacfg.sh \
           file://fpgacfg.service \
           file://active.conf.example \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "fpgacfg.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir} ${D}${docdir}/${BPN}
    install -m 0755 ${WORKDIR}/fpgacfg.sh ${D}${sbindir}/fpgacfg.sh
    install -m 0644 ${WORKDIR}/fpgacfg.service ${D}${systemd_system_unitdir}/fpgacfg.service
    install -m 0644 ${WORKDIR}/active.conf.example ${D}${docdir}/${BPN}/active.conf.example
    sed -i s,@SBINDIR@,${sbindir},g ${D}${systemd_system_unitdir}/fpgacfg.service
}

FILES:${PN} = "${sbindir}/fpgacfg.sh \
               ${systemd_system_unitdir}/fpgacfg.service \
               ${docdir}/${BPN} \
"

RDEPENDS:${PN} = "fpga-manager-script"
