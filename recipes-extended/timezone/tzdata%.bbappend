# Asia/Shanghai is the site timezone for all IMPCAS boards: point
# /etc/localtime at it (relative link; the target ships in the
# tzdata-asia subpackage that ${PN} already depends on) and record the
# zone name in /etc/timezone for tools that read it.
do_install:append() {
    ln -sf ../usr/share/zoneinfo/Asia/Shanghai ${D}${sysconfdir}/localtime
    echo "Asia/Shanghai" > ${D}${sysconfdir}/timezone
}

FILES:${PN} += "${sysconfdir}/localtime ${sysconfdir}/timezone"
