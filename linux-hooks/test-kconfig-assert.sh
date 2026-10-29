#!/bin/sh
# Offline tests for kconfig-assert.sh.
#
# Usage: sh test-kconfig-assert.sh [path-to-kconfig-assert.sh]
#
# The point of these tests is the negative direction: each helper must FAIL on a
# symbol that went missing or silently changed value, because that is the entire
# reason the helpers exist. A helper that always returns success would pass a
# smoke test and protect nothing.

set -u

LIB=${1:-$(dirname "$0")/kconfig-assert.sh}
[ -f "${LIB}" ] || { echo "FATAL: library not found: ${LIB}" >&2; exit 1; }

fails=0
check() {
    if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"
    else printf '  FAIL %s (expected [%s], got [%s])\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

T=$(mktemp -d)
. "${LIB}"

# A representative slice of a real kernel .config, covering every shape the
# helpers have to understand: y, m, "is not set", a string, an integer, and a
# symbol that upstream removed entirely (absent).
cat > "${T}/good.config" <<'CFG'
CONFIG_EXT4_FS=y
CONFIG_XFS_FS=m
# CONFIG_IA32_EMULATION is not set
CONFIG_LOCALVERSION="-theseus-lts"
CONFIG_X86_MINIMUM_CPU_FAMILY=64
CONFIG_SCHED_CLASS_EXT=y
CFG
export T

echo "kassert_y"
( cd "${T}" && cp good.config .config && kassert_y EXT4_FS SCHED_CLASS_EXT >/dev/null 2>&1 )
check "passes on y symbols" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_y XFS_FS >/dev/null 2>&1 )
check "fails on an m symbol" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_y NOT_A_SYMBOL >/dev/null 2>&1 )
check "fails on a missing symbol" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_y EXT4_FS NOT_A_SYMBOL >/dev/null 2>&1 )
check "fails when any one of several is missing" "1" "$?"

echo "kassert_m"
( cd "${T}" && cp good.config .config && kassert_m XFS_FS >/dev/null 2>&1 )
check "passes on m symbols" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_m EXT4_FS >/dev/null 2>&1 )
check "fails on a y symbol" "1" "$?"

echo "kassert_n"
( cd "${T}" && cp good.config .config && kassert_n IA32_EMULATION >/dev/null 2>&1 )
check "passes on 'is not set'" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_n ABSENT_SYMBOL >/dev/null 2>&1 )
check "passes on a symbol upstream removed" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_n EXT4_FS >/dev/null 2>&1 )
check "fails when a y symbol must be off" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_n XFS_FS >/dev/null 2>&1 )
check "fails when an m symbol must be off" "1" "$?"

echo "kassert_str / kassert_val"
( cd "${T}" && cp good.config .config && kassert_str LOCALVERSION '"-theseus-lts"' >/dev/null 2>&1 )
check "passes on exact string with quotes" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_str LOCALVERSION '"-theseus"' >/dev/null 2>&1 )
check "fails on wrong string" "1" "$?"
( cd "${T}" && cp good.config .config && kassert_val X86_MINIMUM_CPU_FAMILY 64 >/dev/null 2>&1 )
check "passes on exact integer" "0" "$?"
( cd "${T}" && cp good.config .config && kassert_val X86_MINIMUM_CPU_FAMILY 32 >/dev/null 2>&1 )
check "fails on wrong integer" "1" "$?"

echo "aborts under sh -e (the mode wright uses)"
( cd "${T}" && cp good.config .config && sh -e -c ". ${LIB}; kassert_y NOT_A_SYMBOL; echo REACHED" >/dev/null 2>&1 )
check "build stops at first failure" "1" "$?"

rm -rf "${T}"
echo
if [ "${fails}" -eq 0 ]; then echo "ALL PASSED"; exit 0; fi
echo "${fails} FAILED"; exit 1
