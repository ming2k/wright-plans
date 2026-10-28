# Shared helpers for the linux plan's transaction hooks.
#
# Sourced by post_install, post_upgrade and pre_remove so that KERNELRELEASE
# resolution and boot-entry pruning exist exactly once. wright executes hooks as
# `/bin/sh -e -c`, so any unguarded failing command aborts the hook; every
# function here handles its own failure and returns a status instead of leaking
# a non-zero exit to the caller.
#
# Layout facts these helpers rely on (Theseus defaults):
#   entry token          "theseus"            /etc/kernel/entry-token
#   UKI directory        /boot/EFI/Linux
#   kernel image path    /boot/vmlinuz-theseus
#   module directories   /usr/lib/modules/<KERNELRELEASE>
#
# Each path lives in an overridable variable so the helpers can be exercised
# against a temporary tree; production code never sets them.

LINUX_BOOT_DIR=${LINUX_BOOT_DIR:-/boot}
LINUX_MODULES_DIR=${LINUX_MODULES_DIR:-/usr/lib/modules}
LINUX_UKI_DIR=${LINUX_UKI_DIR:-${LINUX_BOOT_DIR}/EFI/Linux}
LINUX_BLS_DIR=${LINUX_BLS_DIR:-${LINUX_BOOT_DIR}/loader/entries}
LINUX_IMAGE=${LINUX_IMAGE:-${LINUX_BOOT_DIR}/vmlinuz-theseus}

# kver_installed -- print the newest KERNELRELEASE this plan has installed.
#
# KERNELRELEASE is VERSION.PATCHLEVEL.SUBLEVEL + LOCALVERSION ("7.3.0-theseus"),
# deliberately not "${VERSION}-theseus" ("7.3-theseus"). The module directory is
# named after KERNELRELEASE, so the plan version string must never be used to
# synthesise a directory name.
kver_installed() {
    # sort -V, not plain sort: lexicographic order ranks 7.10 below 7.9 and
    # would register the wrong kernel after an upgrade.
    _ki=$(ls -d "${LINUX_MODULES_DIR}"/*-theseus 2>/dev/null | sort -V | tail -n 1)
    [ -n "${_ki}" ] || return 1
    basename "${_ki}"
}

# kver_from_boot_entry <path> -- print the kernel version a UKI or BLS entry
# belongs to, or nothing when the name does not belong to this plan.
#
# Accepted shapes, all produced by 90-uki-copy.install with the entry token
# "theseus":
#   theseus-7.3.0-theseus.efi
#   theseus-7.3.0-theseus+3.efi     (boot counting)
#   theseus-7.1.8-theseus.conf      (BLS layout)
# linux-lts entries ("-theseus-lts") are rejected on purpose: that plan owns
# them and this one must never prune them.
kver_from_boot_entry() {
    _kb=$(basename "$1")
    _kb=${_kb%.efi}
    _kb=${_kb%.conf}
    _kb=${_kb%+*}
    printf '%s\n' "${_kb}" | sed -nE 's/^.*-([0-9]+\.[0-9]+\.[0-9]+-theseus)$/\1/p'
}

# prune_orphans -- remove boot entries whose module directory no longer exists.
#
# Runs during post_upgrade, after the new kernel's modules are already in place,
# so a freshly installed kernel is never a candidate. The running kernel is
# skipped unconditionally: removing its entry would leave the machine without a
# way to boot what it is currently executing.
prune_orphans() {
    _po_running=$(uname -r)
    for _po_entry in "${LINUX_UKI_DIR}"/*.efi "${LINUX_BLS_DIR}"/*.conf; do
        [ -e "${_po_entry}" ] || continue
        _po_kver=$(kver_from_boot_entry "${_po_entry}")
        # Empty means "not ours" (another plan's image, a fallback, ...).
        [ -n "${_po_kver}" ] || continue
        [ "${_po_kver}" = "${_po_running}" ] && continue
        [ -d "${LINUX_MODULES_DIR}/${_po_kver}" ] && continue
        echo ":: Pruning orphaned boot entry [${_po_kver}]"
        kernel-install remove "${_po_kver}"
    done
}

# register_kernel -- hand the freshly unpacked kernel to kernel-install, which
# runs depmod, dracut, ukify and the ESP copy (install.d/50..90 on this distro).
# Failures propagate so a missing boot entry cannot go unnoticed until reboot.
register_kernel() {
    _rk_kver=$(kver_installed) || {
        echo ":: ERROR: no kernel under ${LINUX_MODULES_DIR}" >&2
        return 1
    }
    if [ ! -f "${LINUX_IMAGE}" ]; then
        echo ":: ERROR: kernel image missing at ${LINUX_IMAGE}" >&2
        return 1
    fi
    echo ":: Registering kernel [${_rk_kver}]"
    kernel-install add "${_rk_kver}" "${LINUX_IMAGE}"
}
