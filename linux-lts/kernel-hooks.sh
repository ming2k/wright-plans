# Shared boot-entry helpers for Theseus kernel plans (linux, linux-lts).
#
# Sourced by every transaction hook of a kernel plan so that KERNELRELEASE
# resolution, boot-entry registration, retired kernel pruning and running-kernel
# protection exist exactly once for all kernels. wright executes hooks as
# `/bin/sh -e -c`, so any unguarded failing command aborts the hook; every
# function here handles its own failure and returns a status instead of leaking a
# non-zero exit to the caller.
#
# A sourcing plan MUST set these two before calling any function:
#
#   LINUX_LOCALVERSION  the LOCALVERSION suffix this plan builds, e.g. "-theseus"
#                       or "-theseus-lts".
#   LINUX_IMAGE         absolute path of the installed kernel image.
#
# LINUX_LOCALVERSION is what keeps the two kernels apart. Every glob and regex
# below is anchored on it, so `linux` can never see, register or prune an
# entry that belongs to `linux-lts`, and vice versa. This matters because the
# two suffixes are prefixes of one another ("-theseus" and "-theseus-lts"), so a
# naive prefix match would let linux claim the LTS kernel.
#
# The remaining paths are defaulted here and only overridden by the test suite,
# which is how these helpers stay testable without touching a real /boot.
# Production hooks never set them.

LINUX_BOOT_DIR=${LINUX_BOOT_DIR:-/boot}
LINUX_MODULES_DIR=${LINUX_MODULES_DIR:-/usr/lib/modules}
LINUX_UKI_DIR=${LINUX_UKI_DIR:-${LINUX_BOOT_DIR}/EFI/Linux}
LINUX_BLS_DIR=${LINUX_BLS_DIR:-${LINUX_BOOT_DIR}/loader/entries}

# require_kernel_install -- fail loudly when systemd's kernel-install is absent.
#
# kernel-install is what runs depmod, dracut, ukify and the ESP copy. Without it
# the kernel lands in /usr/lib/modules with no boot entry at all, which is only
# discovered at the next reboot.
require_kernel_install() {
    command -v kernel-install >/dev/null 2>&1 && return 0
    echo ":: ERROR: kernel-install not found; cannot manage the boot entry" >&2
    return 1
}

# _linux_suffix_re -- print LINUX_LOCALVERSION escaped for use in a sed -E regex.
_linux_suffix_re() {
    printf '%s\n' "${LINUX_LOCALVERSION}" | sed 's/[]\/$*.^[]/\\&/g'
}

# kver_installed -- print the newest KERNELRELEASE this plan has installed.
#
# KERNELRELEASE is VERSION.PATCHLEVEL.SUBLEVEL + LOCALVERSION
# ("6.18.59-theseus-lts"), deliberately not "${VERSION}-theseus-lts"
# ("6.18.59-theseus-lts" only by coincidence). The module directory is named
# after KERNELRELEASE, so the plan version string must never be used to
# synthesise a directory name: plan version "6.18.59" and kernel release
# "6.18.59-theseus-lts" are different strings, and a release with a non-zero
# SUBLEVEL (e.g. plan 6.18 -> release 6.18.59) makes them diverge outright.
kver_installed() {
    # sort -V, not plain sort: lexicographic order ranks 6.18.10 below 6.18.9 and
    # would register the wrong kernel after an upgrade.
    _ki=$(ls -d "${LINUX_MODULES_DIR}"/*"${LINUX_LOCALVERSION}" 2>/dev/null | sort -V | tail -n 1)
    [ -n "${_ki}" ] || return 1
    basename "${_ki}"
}

# kver_from_boot_entry <path> -- print the kernel version a UKI or BLS entry
# belongs to, or nothing when the entry does not belong to this plan.
#
# Accepted shapes, all produced by systemd's 90-uki-copy.install / 90-loaderentry
# with an entry token of "theseus":
#   theseus-6.18.59-theseus-lts.efi
#   theseus-6.18.59-theseus-lts+3.efi     (boot counting)
#   theseus-6.18.59-theseus-lts.conf      (BLS layout)
# Anything else -- the other kernel's entries, a memtest image, a fallback --
# prints nothing, so callers skip it.
kver_from_boot_entry() {
    _kb=$(basename "$1")
    _kb=${_kb%.efi}
    _kb=${_kb%.conf}
    _kb=${_kb%+*}
    _kr=$(_linux_suffix_re)
    printf '%s\n' "${_kb}" | sed -nE "s/^.*-([0-9]+\.[0-9]+\.[0-9]+${_kr})\$/\1/p"
}

# register_kernel -- hand the freshly unpacked kernel to kernel-install, which
# runs depmod, dracut, ukify and the ESP copy.
#
# Failures propagate so a missing boot entry cannot go unnoticed until reboot.
register_kernel() {
    _rk_kver=$(kver_installed) || {
        echo ":: ERROR: no kernel under ${LINUX_MODULES_DIR} matching *${LINUX_LOCALVERSION}" >&2
        return 1
    }
    if [ ! -f "${LINUX_IMAGE}" ]; then
        echo ":: ERROR: kernel image missing at ${LINUX_IMAGE}" >&2
        return 1
    fi
    echo ":: Registering kernel [${_rk_kver}]"
    kernel-install add "${_rk_kver}" "${LINUX_IMAGE}"
}

# prune_retired_kernels -- keep only the newest target version and the running
# kernel for this package's LOCALVERSION series, retiring all older versions.
#
# This enforces the Keep-1 policy across both:
#   1. ESP bootloader entries (/boot/EFI/Linux/*.efi, loader/entries/*.conf)
#   2. Module trees on disk (/usr/lib/modules/<old_kver>)
#
# Why this replaces the passive prune_orphans:
#   `prune_orphans` only deleted a boot entry if its module directory was ALREADY
#   gone from /usr/lib/modules/. If an old module directory remained (e.g. from
#   a bootstrap stage, untracked index files, or historical leftovers), neither
#   the modules nor the boot entry was ever deleted.
#
# Safety invariants enforced here:
#   - NEVER prune the freshly registered kernel (_pr_target)
#   - NEVER prune the currently running kernel (uname -r)
#   - ONLY inspect entries and directories matching our own LINUX_LOCALVERSION;
#     linux and linux-lts can never touch each other's files.
prune_retired_kernels() {
    _pr_target=$(kver_installed 2>/dev/null || true)
    _pr_running=$(uname -r)

    # 1. Prune retired boot entries from ESP / bootloader
    for _pr_entry in "${LINUX_UKI_DIR}"/*.efi "${LINUX_BLS_DIR}"/*.conf; do
        [ -e "${_pr_entry}" ] || continue
        _pr_kver=$(kver_from_boot_entry "${_pr_entry}")
        [ -n "${_pr_kver}" ] || continue
        [ -n "${_pr_target}" ] && [ "${_pr_kver}" = "${_pr_target}" ] && continue
        [ "${_pr_kver}" = "${_pr_running}" ] && continue
        echo ":: Pruning retired boot entry [${_pr_kver}]"
        kernel-install remove "${_pr_kver}"
    done

    # 2. Prune retired module directories from /usr/lib/modules
    for _pr_mod_dir in "${LINUX_MODULES_DIR}"/*"${LINUX_LOCALVERSION}"; do
        [ -d "${_pr_mod_dir}" ] || continue
        _pr_mod_kver=$(basename "${_pr_mod_dir}")
        [ -n "${_pr_target}" ] && [ "${_pr_mod_kver}" = "${_pr_target}" ] && continue
        [ "${_pr_mod_kver}" = "${_pr_running}" ] && continue
        echo ":: Pruning retired kernel modules [${_pr_mod_kver}]"
        rm -rf "${_pr_mod_dir}"
    done
}

# prune_orphans -- backward compatibility alias for prune_retired_kernels.
prune_orphans() {
    prune_retired_kernels "$@"
}

# remove_kernel -- drop this plan's boot entry, unless it is the running kernel.
#
# Used by pre_remove. Refusing to remove the running kernel's entry is not
# politeness: it is the only entry that can boot the machine as it currently is,
# and the module directory disappears right after this hook, so an accidental
# removal is unrecoverable from the installed system.
remove_kernel() {
    _rm_kver=$(kver_installed) || {
        echo ":: No installed *${LINUX_LOCALVERSION} kernel found; nothing to remove"
        return 0
    }
    if [ "${_rm_kver}" = "$(uname -r)" ]; then
        echo ":: Keeping boot entry [${_rm_kver}]: it is the running kernel"
        return 0
    fi
    echo ":: Removing boot entry [${_rm_kver}]"
    kernel-install remove "${_rm_kver}"
}
