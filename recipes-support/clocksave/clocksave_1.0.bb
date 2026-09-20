SUMMARY = "Persist the system clock across reboots without an RTC"
DESCRIPTION = "Restores the last known time from /boot/clock.save early at \
boot and saves the current time at start, at shutdown and on a timer, so \
boards without an RTC do not boot into the distant past while NTP is not \
yet reachable. Saves only ever move the timestamp forward, so a stale \
kernel-default clock can never overwrite a good value."
HOMEPAGE = "https://github.com/ra9fael/meta-impcas-util"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://clocksave.sh \
           file://clocksave-restore.service \
           file://clocksave-save.service \
           file://clocksave-periodic.service \
           file://clocksave.timer \
"

S = "${WORKDIR}"

inherit systemd

# clocksave-periodic.service is installed but deliberately not listed: it
# has no [Install] section and is only triggered by the timer.
SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "clocksave-restore.service \
                         clocksave-save.service \
                         clocksave.timer \
"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${WORKDIR}/clocksave.sh ${D}${sbindir}/clocksave.sh
    install -m 0644 ${WORKDIR}/clocksave-restore.service ${D}${systemd_system_unitdir}/clocksave-restore.service
    install -m 0644 ${WORKDIR}/clocksave-save.service ${D}${systemd_system_unitdir}/clocksave-save.service
    install -m 0644 ${WORKDIR}/clocksave-periodic.service ${D}${systemd_system_unitdir}/clocksave-periodic.service
    install -m 0644 ${WORKDIR}/clocksave.timer ${D}${systemd_system_unitdir}/clocksave.timer
    sed -i s,@SBINDIR@,${sbindir},g ${D}${systemd_system_unitdir}/clocksave-*.service
}

FILES:${PN} = "${sbindir}/clocksave.sh ${systemd_system_unitdir}/clocksave*"
