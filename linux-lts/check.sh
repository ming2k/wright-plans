#!/bin/sh
# Self-contained offline test suite for the linux-lts kernel plan.
#
# Verifies:
#   1. Shell syntax of all pipeline scripts and transaction hooks (sh -n)
#   2. The kernel-hooks decision table (version sorting, boot counting, Keep-1
#      active pruning, running-kernel protection, require_kernel_install)
#   3. The kconfig assertion helpers (kassert_y/m/n/str/val and negative failures)
#   4. Agreement between README.md CONFIG_ claims and config baseline
#
# Runs fully offline: no root, no real /boot, no kernel build.
# Usage: sh check.sh

set -u

DIR=$(cd "$(dirname "$0")" && pwd)
cd "${DIR}"

fails=0
check() {
    if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"
    else printf '  FAIL %s (expected [%s], got [%s])\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

# ---------------------------------------------------------------- 1. Syntax
printf '== 1. Pipeline & Hooks Syntax ==\n'
python3 - <<'PY' || fails=$((fails + 1))
import tomllib, subprocess, tempfile, os, sys
d = tomllib.load(open('plan.toml', 'rb'))
bad = 0
for st, cfg in d.get('pipeline', {}).items():
    if not cfg.get('script'): continue
    f = tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False); f.write(cfg['script']); f.close()
    r = subprocess.run(['sh', '-n', f.name], capture_output=True, text=True); os.unlink(f.name)
    if r.returncode: print(f"  FAIL pipeline.{st}: {r.stderr.strip()}"); bad += 1
    else: print(f"  ok   pipeline.{st}")
for out in d.get('output', []):
    for hk, hv in out.get('hooks', {}).items():
        f = tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False); f.write(hv); f.close()
        r = subprocess.run(['sh', '-n', f.name], capture_output=True, text=True); os.unlink(f.name)
        if r.returncode: print(f"  FAIL hooks.{hk}: {r.stderr.strip()}"); bad += 1
        else: print(f"  ok   hooks.{hk}")
sys.exit(1 if bad else 0)
PY

# ------------------------------------------------------- 2. Kconfig Assert
printf '\n== 2. Kconfig Assertion Helpers ==\n'
T=$(mktemp -d)
. ./kconfig-assert.sh
cat > "${T}/good.config" <<'CFG'
CONFIG_EXT4_FS=y
CONFIG_XFS_FS=m
# CONFIG_IA32_EMULATION is not set
CONFIG_LOCALVERSION="-theseus-lts"
CONFIG_X86_MINIMUM_CPU_FAMILY=64
CONFIG_SCHED_CLASS_EXT=y
CFG

( cd "${T}" && cp good.config .config && kassert_y EXT4_FS SCHED_CLASS_EXT >/dev/null 2>&1 )
check "kassert_y passes on y symbols" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_y XFS_FS >/dev/null 2>&1 )
check "kassert_y fails on an m symbol" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_y NOT_A_SYMBOL >/dev/null 2>&1 )
check "kassert_y fails on a missing symbol" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_m XFS_FS >/dev/null 2>&1 )
check "kassert_m passes on m symbols" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_m EXT4_FS >/dev/null 2>&1 )
check "kassert_m fails on a y symbol" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_n IA32_EMULATION >/dev/null 2>&1 )
check "kassert_n passes on 'is not set'" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_n ABSENT_SYMBOL >/dev/null 2>&1 )
check "kassert_n passes on absent symbol" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_n EXT4_FS >/dev/null 2>&1 )
check "kassert_n fails when y is present" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_str LOCALVERSION '"-theseus-lts"' >/dev/null 2>&1 )
check "kassert_str passes on exact string" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_str LOCALVERSION '"-theseus"' >/dev/null 2>&1 )
check "kassert_str fails on wrong string" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_val X86_MINIMUM_CPU_FAMILY 64 >/dev/null 2>&1 )
check "kassert_val passes on exact integer" "0" "$?"
( cd "${T}" && cp good.config .config && sh -e -c ". ${DIR}/kconfig-assert.sh; kassert_y BAD_SYM; echo REACHED" >/dev/null 2>&1 )
check "kassert aborts under sh -e" "1" "$?"
rm -rf "${T}"

# --------------------------------------------------------- 3. Kernel Hooks
printf '\n== 3. Kernel Hooks (Keep-1 & Isolation) ==\n'
T=$(mktemp -d)
mkdir -p "${T}/modules" "${T}/uki" "${T}/entries" "${T}/bin"
: > "${T}/ki.log"
cat > "${T}/bin/kernel-install" <<'STUB'
#!/bin/sh
cmd="$1"; ver="$2"
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
PATH="${T}/bin:${PATH}"; export PATH

. ./kernel-hooks.sh

# Sorting
LINUX_LOCALVERSION="-theseus-lts"; export LINUX_LOCALVERSION
mkdir -p "${LINUX_MODULES_DIR}/6.18.9-theseus-lts" "${LINUX_MODULES_DIR}/6.18.10-theseus-lts"
check "sort -V picks 6.18.10 over 6.18.9" "6.18.10-theseus-lts" "$(kver_installed)"
mkdir -p "${LINUX_MODULES_DIR}/7.3.0-theseus"
check "-theseus-lts ignores -theseus dirs" "6.18.10-theseus-lts" "$(kver_installed)"

# Name parsing
check "plain UKI" "6.18.59-theseus-lts" "$(kver_from_boot_entry "${T}/uki/theseus-6.18.59-theseus-lts.efi")"
check "boot counting +3" "6.18.59-theseus-lts" "$(kver_from_boot_entry "${T}/uki/theseus-6.18.59-theseus-lts+3.efi")"
check "rolling entry rejected" "" "$(kver_from_boot_entry "${T}/uki/theseus-7.3.0-theseus.efi")"
check "foreign entry rejected" "" "$(kver_from_boot_entry "${T}/uki/memtest86.efi")"

# Keep-1 active pruning
mkdir -p "${LINUX_MODULES_DIR}/6.18.24-theseus-lts" "${LINUX_MODULES_DIR}/6.18.44-theseus-lts" "${LINUX_MODULES_DIR}/6.18.59-theseus-lts"
touch "${LINUX_UKI_DIR}/theseus-6.18.24-theseus-lts.efi" "${LINUX_UKI_DIR}/theseus-6.18.44-theseus-lts.efi" "${LINUX_UKI_DIR}/theseus-6.18.59-theseus-lts.efi"
touch "${LINUX_UKI_DIR}/theseus-7.3.0-theseus.efi" "${LINUX_UKI_DIR}/memtest86.efi"

prune_retired_kernels >/dev/null
check "target 6.18.59 UKI kept" "yes" "$([ -f "${LINUX_UKI_DIR}/theseus-6.18.59-theseus-lts.efi" ] && echo yes || echo no)"
check "target 6.18.59 modules kept" "yes" "$([ -d "${LINUX_MODULES_DIR}/6.18.59-theseus-lts" ] && echo yes || echo no)"
check "retired 6.18.24 UKI removed" "no" "$([ -f "${LINUX_UKI_DIR}/theseus-6.18.24-theseus-lts.efi" ] && echo yes || echo no)"
check "retired 6.18.24 modules removed" "no" "$([ -d "${LINUX_MODULES_DIR}/6.18.24-theseus-lts" ] && echo yes || echo no)"
check "retired 6.18.44 UKI removed" "no" "$([ -f "${LINUX_UKI_DIR}/theseus-6.18.44-theseus-lts.efi" ] && echo yes || echo no)"
check "retired 6.18.44 modules removed" "no" "$([ -d "${LINUX_MODULES_DIR}/6.18.44-theseus-lts" ] && echo yes || echo no)"
check "rolling UKI untouched" "yes" "$([ -f "${LINUX_UKI_DIR}/theseus-7.3.0-theseus.efi" ] && echo yes || echo no)"
check "foreign memtest untouched" "yes" "$([ -f "${LINUX_UKI_DIR}/memtest86.efi" ] && echo yes || echo no)"

# Running kernel protection
running=$(uname -r)
mkdir -p "${LINUX_MODULES_DIR}/${running}" "${LINUX_MODULES_DIR}/99.0.0-theseus-lts"
touch "${LINUX_UKI_DIR}/theseus-${running}.efi" "${LINUX_UKI_DIR}/theseus-99.0.0-theseus-lts.efi"
prune_retired_kernels >/dev/null
check "running kernel UKI kept" "yes" "$([ -f "${LINUX_UKI_DIR}/theseus-${running}.efi" ] && echo yes || echo no)"
check "running kernel modules kept" "yes" "$([ -d "${LINUX_MODULES_DIR}/${running}" ] && echo yes || echo no)"

# Registration & remove
: > "${LINUX_IMAGE}"
: > "${KI_LOG}"
register_kernel >/dev/null
check "register_kernel adds newest" "yes" "$(grep -q "add 99.0.0-theseus-lts" "${KI_LOG}" && echo yes || echo no)"
remove_kernel >/dev/null
check "remove_kernel does not delete running" "yes" "$(! grep -q "remove ${running}" "${KI_LOG}" && echo yes || echo no)"

# require_kernel_install
require_kernel_install >/dev/null 2>&1
check "require_kernel_install succeeds when present" "0" "$?"
rm -rf "${T}"

# --------------------------------------------------------- 4. README vs Config
printf '\n== 4. README vs Config Consistency ==\n'
config_val() {
    _cv=$(grep -E "^CONFIG_$1=" config | head -1 | cut -d= -f2-)
    if [ -n "${_cv}" ]; then printf '%s' "${_cv}"; return; fi
    if grep -qx "# CONFIG_$1 is not set" config; then printf 'n'; return; fi
    printf 'ABSENT'
}

rm_fails=0
rm_checked=0
section=normal
while IFS= read -r line; do
    case "${line}" in
        "Deliberately **not** enabled"*) section=negative; continue ;;
        "## "*) section=normal; continue ;;
    esac
    for tok in $(printf '%s\n' "${line}" | grep -oE 'CONFIG_[A-Z0-9_]+(=[^` ,;)]*)?' | sed 's/[`.,;:)]*$//'); do
        sym=${tok%%=*}; sym=${sym#CONFIG_}
        [ -n "${sym}" ] || continue
        want=""
        case "${tok}" in *=*) want=${tok#*=} ;; esac
        have=$(config_val "${sym}")
        rm_checked=$((rm_checked + 1))
        if [ "${section}" = negative ]; then
            case "${have}" in
                y|m) printf '  FAIL README disabled CONFIG_%s but config has %s\n' "${sym}" "${have}"; rm_fails=$((rm_fails+1)) ;;
            esac
            continue
        fi
        if [ "${have}" = ABSENT ]; then
            printf '  FAIL README names CONFIG_%s but config has no such symbol\n' "${sym}"; rm_fails=$((rm_fails+1))
        elif [ -n "${want}" ] && [ "${have}" != "${want}" ]; then
            printf '  FAIL README claims CONFIG_%s=%s but config has %s\n' "${sym}" "${want}" "${have}"; rm_fails=$((rm_fails+1))
        fi
    done
done < README.md

check "README vs config: ${rm_checked} symbols checked" "0" "${rm_fails}"

printf '\n'
if [ "${fails}" -eq 0 ]; then
    echo "ALL LINUX-LTS CHECKS PASSED"
    exit 0
fi
echo "${fails} CHECK(S) FAILED"
exit 1
