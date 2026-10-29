#!/bin/sh
# Offline test harness for kernel-hooks.sh.
#
# Exercises the whole decision table against a temporary tree, so the boot-entry
# logic can be verified without a real /boot, without root, and without building
# a kernel. Every path the library touches is redirected through the
# ${VAR:-default} knobs it exposes.
#
# Usage: sh test-kernel-hooks.sh [path-to-kernel-hooks.sh]
#
# Exit status: 0 when every case passes, 1 otherwise. Suitable for CI.

set -u

LIB=${1:-$(dirname "$0")/kernel-hooks.sh}
[ -f "${LIB}" ] || { echo "FATAL: library not found: ${LIB}" >&2; exit 1; }

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# check <description> <expected> <actual>
check() {
    if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected [$2], got [$3])"; fi
}

# stub_kernel_install -- put a fake kernel-install first in PATH that records its
# arguments and simulates removing UKI files.
setup() {
    T=$(mktemp -d)
    mkdir -p "${T}/modules" "${T}/uki" "${T}/entries" "${T}/bin"
    : > "${T}/ki.log"
    cat > "${T}/bin/kernel-install" <<'STUB'
#!/bin/sh
cmd="$1"
ver="$2"
if [ "$cmd" = "remove" ]; then
    rm -f "${LINUX_UKI_DIR}/theseus-${ver}.efi" "${LINUX_UKI_DIR}/theseus-${ver}+"*.efi
    rm -f "${LINUX_BLS_DIR}/theseus-${ver}.conf"
fi
echo "$*" >> "$KI_LOG"
STUB
    chmod +x "${T}/bin/kernel-install"

    LINUX_MODULES_DIR="${T}/modules"
    LINUX_UKI_DIR="${T}/uki"
    LINUX_BLS_DIR="${T}/entries"
    LINUX_BOOT_DIR="${T}"
    LINUX_IMAGE="${T}/vmlinuz"
    export LINUX_MODULES_DIR LINUX_UKI_DIR LINUX_BLS_DIR LINUX_BOOT_DIR LINUX_IMAGE
    export KI_LOG="${T}/ki.log"
    PATH="${T}/bin:${PATH}"
    export PATH
}

# ---------------------------------------------------------------- sort -V
echo "kver_installed (version sorting)"
setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION
mkdir -p "${LINUX_MODULES_DIR}/6.18.9-theseus" "${LINUX_MODULES_DIR}/6.18.10-theseus"
check "sort -V picks 6.18.10, not 6.18.9" "6.18.10-theseus" "$(kver_installed)"
# A suffix that is a prefix of another must not be confused.
mkdir -p "${LINUX_MODULES_DIR}/6.19.0-theseus-lts"
check "-theseus ignores -theseus-lts dirs" "6.18.10-theseus" "$(kver_installed)"
LINUX_LOCALVERSION="-theseus-lts"
export LINUX_LOCALVERSION
check "-theseus-lts sees only its own dirs" "6.19.0-theseus-lts" "$(kver_installed)"
rm -rf "${T}"

# ------------------------------------------------- entry name parsing
echo "kver_from_boot_entry (name parsing)"
setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION
check "plain UKI"            "6.18.59-theseus" "$(kver_from_boot_entry "${T}/uki/theseus-6.18.59-theseus.efi")"
check "boot counting +3"     "6.18.59-theseus" "$(kver_from_boot_entry "${T}/uki/theseus-6.18.59-theseus+3.efi")"
check "BLS .conf"            "6.18.59-theseus" "$(kver_from_boot_entry "${T}/entries/theseus-6.18.59-theseus.conf")"
check "foreign file rejected" ""               "$(kver_from_boot_entry "${T}/uki/memtest86.efi")"
check "LTS entry rejected"    ""               "$(kver_from_boot_entry "${T}/uki/theseus-6.18.59-theseus-lts.efi")"
LINUX_LOCALVERSION="-theseus-lts"
export LINUX_LOCALVERSION
check "-theseus-lts accepts its own" "6.18.59-theseus-lts" "$(kver_from_boot_entry "${T}/uki/theseus-6.18.59-theseus-lts.efi")"
check "-theseus-lts rejects plain"   ""                    "$(kver_from_boot_entry "${T}/uki/theseus-6.18.59-theseus.efi")"
rm -rf "${T}"

# --------------------------------------------- prune_retired_kernels (Keep-1)
echo "prune_retired_kernels (Keep-1 active policy)"
setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus-lts"
export LINUX_LOCALVERSION

# Populate 3 LTS kernels (2 retired, 1 new target) and 1 rolling kernel
mkdir -p "${LINUX_MODULES_DIR}/6.18.24-theseus-lts"
mkdir -p "${LINUX_MODULES_DIR}/6.18.44-theseus-lts"
mkdir -p "${LINUX_MODULES_DIR}/6.18.59-theseus-lts"
mkdir -p "${LINUX_MODULES_DIR}/7.3.0-theseus"

touch "${LINUX_UKI_DIR}/theseus-6.18.24-theseus-lts.efi"
touch "${LINUX_UKI_DIR}/theseus-6.18.44-theseus-lts.efi"
touch "${LINUX_UKI_DIR}/theseus-6.18.59-theseus-lts.efi"
touch "${LINUX_UKI_DIR}/theseus-7.3.0-theseus.efi"
touch "${LINUX_UKI_DIR}/memtest86.efi"

prune_retired_kernels >/dev/null

check "target 6.18.59 UKI kept" "yes" "$([ -f "${LINUX_UKI_DIR}/theseus-6.18.59-theseus-lts.efi" ] && echo yes || echo no)"
check "target 6.18.59 modules kept" "yes" "$([ -d "${LINUX_MODULES_DIR}/6.18.59-theseus-lts" ] && echo yes || echo no)"
check "retired 6.18.24 UKI removed" "no" "$([ -f "${LINUX_UKI_DIR}/theseus-6.18.24-theseus-lts.efi" ] && echo yes || echo no)"
check "retired 6.18.24 modules removed" "no" "$([ -d "${LINUX_MODULES_DIR}/6.18.24-theseus-lts" ] && echo yes || echo no)"
check "retired 6.18.44 UKI removed" "no" "$([ -f "${LINUX_UKI_DIR}/theseus-6.18.44-theseus-lts.efi" ] && echo yes || echo no)"
check "retired 6.18.44 modules removed" "no" "$([ -d "${LINUX_MODULES_DIR}/6.18.44-theseus-lts" ] && echo yes || echo no)"
check "other series 7.3.0 UKI untouched" "yes" "$([ -f "${LINUX_UKI_DIR}/theseus-7.3.0-theseus.efi" ] && echo yes || echo no)"
check "other series 7.3.0 modules untouched" "yes" "$([ -d "${LINUX_MODULES_DIR}/7.3.0-theseus" ] && echo yes || echo no)"
check "foreign memtest untouched" "yes" "$([ -f "${LINUX_UKI_DIR}/memtest86.efi" ] && echo yes || echo no)"
rm -rf "${T}"

# ------------------------------------------------ running kernel protection
echo "running kernel protection during upgrade"
setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION

running=$(uname -r)
mkdir -p "${LINUX_MODULES_DIR}/${running}"
mkdir -p "${LINUX_MODULES_DIR}/99.0.0-theseus" # newer target
touch "${LINUX_UKI_DIR}/theseus-${running}.efi"
touch "${LINUX_UKI_DIR}/theseus-99.0.0-theseus.efi"

prune_retired_kernels >/dev/null

check "running kernel UKI kept" "yes" "$([ -f "${LINUX_UKI_DIR}/theseus-${running}.efi" ] && echo yes || echo no)"
check "running kernel modules kept" "yes" "$([ -d "${LINUX_MODULES_DIR}/${running}" ] && echo yes || echo no)"
check "new target UKI kept" "yes" "$([ -f "${LINUX_UKI_DIR}/theseus-99.0.0-theseus.efi" ] && echo yes || echo no)"
check "new target modules kept" "yes" "$([ -d "${LINUX_MODULES_DIR}/99.0.0-theseus" ] && echo yes || echo no)"
rm -rf "${T}"

# --------------------------------------------------------- register
echo "register_kernel"
setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION
mkdir -p "${LINUX_MODULES_DIR}/6.18.10-theseus"
: > "${LINUX_IMAGE}"
register_kernel >/dev/null
check "registers newest with image" "add 6.18.10-theseus ${LINUX_IMAGE}" "$(cat "${KI_LOG}")"
rm -rf "${T}"

setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION
register_kernel >/dev/null 2>&1
check "fails when no modules installed" "1" "$?"
rm -rf "${T}"

setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION
mkdir -p "${LINUX_MODULES_DIR}/6.18.10-theseus"
register_kernel >/dev/null 2>&1
check "fails when image missing" "1" "$?"
rm -rf "${T}"

# ---------------------------------------------------------- remove
echo "remove_kernel (running-kernel guard)"
setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION
running=$(uname -r)
mkdir -p "${LINUX_MODULES_DIR}/${running}"
remove_kernel >/dev/null
check "running kernel entry kept" "" "$(cat "${KI_LOG}")"
rm -rf "${T}"

setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION
mkdir -p "${LINUX_MODULES_DIR}/6.18.10-theseus"
remove_kernel >/dev/null
check "non-running kernel removed" "remove 6.18.10-theseus" "$(cat "${KI_LOG}")"
rm -rf "${T}"

setup
. "${LIB}"
LINUX_LOCALVERSION="-theseus"
export LINUX_LOCALVERSION
remove_kernel >/dev/null 2>&1
check "no kernel installed is not an error" "0" "$?"
rm -rf "${T}"

# ------------------------------------------------- require_kernel_install
echo "require_kernel_install"
setup
. "${LIB}"
require_kernel_install >/dev/null 2>&1
check "present" "0" "$?"
rm -rf "${T}"
setup
cp "${LIB}" "${T}/lib.sh"
_SAVED_PATH=${PATH}
. "${T}/lib.sh"
PATH="/nonexistent"
require_kernel_install >/dev/null 2>&1
check "absent fails" "1" "$?"
PATH=${_SAVED_PATH}
export PATH
rm -rf "${T}"

echo
if [ "${fails}" -eq 0 ]; then
    echo "ALL PASSED"
    exit 0
fi
echo "${fails} FAILED"
exit 1
