SUMMARY = "Load the selected FPGA bitstream from /boot/fpga at boot"
DESCRIPTION = "Configures the PL through Xilinx fpgautil with the bitstream \
selected by /boot/fpga/active.conf out of a pool of bitstream files on the \
writable BOOT partition, so a bitstream can be swapped per machine without \
rebuilding the rootfs. The selection is an exact pool file name or a glob \
pattern (* / ?), matched case-insensitively like the FAT32 BOOT partition; \
a pattern matching several files loads the newest one by modification \
time. The script also accepts a file-name argument to load a pool file at \
runtime. A deployment that loads the PL from BOOT.BIN (FSBL) \
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

inherit systemd deploy

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "fpgacfg.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir} ${D}${datadir}/${BPN}
    install -m 0755 ${WORKDIR}/fpgacfg.sh ${D}${sbindir}/fpgacfg.sh
    install -m 0644 ${WORKDIR}/fpgacfg.service ${D}${systemd_system_unitdir}/fpgacfg.service
    install -m 0644 ${WORKDIR}/active.conf.example ${D}${datadir}/${BPN}/active.conf.example
    sed -i s,@SBINDIR@,${sbindir},g ${D}${systemd_system_unitdir}/fpgacfg.service
}

FILES:${PN} = "${sbindir}/fpgacfg.sh \
               ${systemd_system_unitdir}/fpgacfg.service \
               ${datadir}/${BPN} \
"

RDEPENDS:${PN} = "fpga-manager-script"

# Staged into DEPLOY_DIR_IMAGE and copied into the project's images/linux
# by PetaLinux's plnx-deploy machinery (plnx_deploy postfunc, same as
# u-boot/device-tree), mirroring the target layout (BOOT partition):
# fpga/active.conf.example is renamed and edited per machine; the bitstream
# pool (*.bin) itself is per-machine content that cannot come from the
# build.
do_deploy() {
    install -d ${DEPLOYDIR}/fpga
    install -m 0644 ${WORKDIR}/active.conf.example ${DEPLOYDIR}/fpga/active.conf.example
}
addtask deploy after do_install before do_build
do_deploy[postfuncs] += "plnx_deploy"
do_deploy_setscene[postfuncs] += "plnx_deploy"
PACKAGES_LIST[fpgacfg] = "fpga:fpga"
