SUMMARY = "Machine identity, network and NTP configuration from /boot/machine/machine.cfg"
DESCRIPTION = "Translates a per-machine KEY=value file on the writable BOOT \
partition into runtime systemd-networkd and systemd-timesyncd configuration \
under /run, so a read-only rootfs image stays identical across machines. \
Addressing is static by default (IPADDRESS takes one or more addresses, each \
optionally suffixed /prefix); DHCP=ipv4 only when DHCP=yes, which ignores \
the static address keys. The .network drop-in is written only when it \
configures addressing, so an NTP-only machine.cfg cannot shadow the \
built-in 80-wired.network. Time servers are applied to the highest-priority \
daemon present (chronyd > ntpd > systemd-timesyncd); the others are \
configured too but disabled."
HOMEPAGE = "https://github.com/ra9fael/meta-impcas-util"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://bootcfg.sh \
           file://bootcfg.service \
           file://machine.cfg.example \
"

S = "${WORKDIR}"

inherit systemd deploy

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "bootcfg.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir} ${D}${datadir}/${BPN}
    install -m 0755 ${WORKDIR}/bootcfg.sh ${D}${sbindir}/bootcfg.sh
    install -m 0644 ${WORKDIR}/bootcfg.service ${D}${systemd_system_unitdir}/bootcfg.service
    install -m 0644 ${WORKDIR}/machine.cfg.example ${D}${datadir}/${BPN}/machine.cfg.example
    sed -i s,@SBINDIR@,${sbindir},g ${D}${systemd_system_unitdir}/bootcfg.service
}

FILES:${PN} = "${sbindir}/bootcfg.sh \
               ${systemd_system_unitdir}/bootcfg.service \
               ${datadir}/${BPN} \
"

# The .example template is staged into DEPLOY_DIR_IMAGE and copied into the
# project's images/linux by PetaLinux's plnx-deploy machinery (plnx_deploy
# postfunc, same as u-boot/device-tree), under a machine/ directory that
# mirrors the target layout, so inflate-sd.sh can put it on the BOOT
# partition. Rename and edit it per machine (machine/machine.cfg) before
# first boot.
do_deploy() {
    install -d ${DEPLOYDIR}/machine
    install -m 0644 ${WORKDIR}/machine.cfg.example ${DEPLOYDIR}/machine/machine.cfg.example
}
addtask deploy after do_install before do_build
do_deploy[postfuncs] += "plnx_deploy"
do_deploy_setscene[postfuncs] += "plnx_deploy"
PACKAGES_LIST[bootcfg] = "machine:machine"
