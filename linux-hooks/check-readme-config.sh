#!/bin/sh
# Verify that README claims about CONFIG_ symbols match the maintained config.
#
# Usage: sh check-readme-config.sh <plan-dir>
#
# Why this exists: a kernel README is the document a maintainer reads before
# changing anything, and it drifts silently. This plan's README claimed
# CONFIG_RUST=y, CONFIG_LTO_CLANG_THIN=y, CONFIG_CET=y and "AppArmor support
# enabled" while `config` carried none of those symbols. Nothing failed, so
# nobody noticed for months. Prose cannot be enforced; a check can.
#
# What is checked:
#   * every CONFIG_ token in the README's normal sections must exist in `config`,
#     and must match when the README states a value (CONFIG_X=y)
#   * CONFIG_ tokens inside the "Deliberately not enabled" section must genuinely
#     not be y/m, so a symbol can be documented as off and stay honest even when
#     upstream removes it entirely
#
# Exit status: 0 when consistent, 1 on any mismatch.

set -u

PLAN=${1:-.}
README="${PLAN}/README.md"
CONFIG="${PLAN}/config"

[ -f "${README}" ] || { echo "FATAL: no README at ${README}" >&2; exit 1; }
[ -f "${CONFIG}" ] || { echo "FATAL: no config at ${CONFIG}" >&2; exit 1; }

fails=0
checked=0
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# config_value <SYMBOL> -- y / m / n / other-value / ABSENT
config_value() {
    _cv=$(grep -E "^CONFIG_$1=" "${CONFIG}" | head -1 | cut -d= -f2-)
    if [ -n "${_cv}" ]; then printf '%s' "${_cv}"; return; fi
    if grep -qx "# CONFIG_$1 is not set" "${CONFIG}"; then printf 'n'; return; fi
    printf 'ABSENT'
}

section=normal
while IFS= read -r line; do
    case "${line}" in
        "Deliberately **not** enabled"*) section=negative; continue ;;
        "## "*) section=normal; continue ;;
    esac

    # Extract backticked and bare CONFIG_ tokens, dropping trailing punctuation.
    for tok in $(printf '%s\n' "${line}" \
                 | grep -oE 'CONFIG_[A-Z0-9_]+(=[^` ,;)]*)?' \
                 | sed 's/[`.,;:)]*$//'); do
        sym=${tok%%=*}
        sym=${sym#CONFIG_}
        [ -n "${sym}" ] || continue
        want=""
        case "${tok}" in *=*) want=${tok#*=} ;; esac

        have=$(config_value "${sym}")
        checked=$((checked + 1))

        if [ "${section}" = negative ]; then
            case "${have}" in
                y|m) fail "README documents CONFIG_${sym} as disabled but config has ${have}" ;;
            esac
            continue
        fi

        if [ "${have}" = ABSENT ]; then
            fail "README names CONFIG_${sym} but config has no such symbol"
        elif [ -n "${want}" ] && [ "${have}" != "${want}" ]; then
            fail "README claims CONFIG_${sym}=${want} but config has ${have}"
        fi
    done
done < "${README}"

echo "checked ${checked} CONFIG_ token(s) in ${README}"
if [ "${fails}" -eq 0 ]; then
    echo "README/config consistent"
    exit 0
fi
echo "${fails} mismatch(es)"
exit 1
