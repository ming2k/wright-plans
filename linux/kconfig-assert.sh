# Assertion helpers for Theseus kernel plans.
#
# These exist to separate two things that `scripts/config --enable` conflates:
#
#   SET    -- force a value that is NOT in the maintained config baseline.
#   ASSERT -- require a value that IS in the baseline, and refuse to build if it
#             did not survive `make olddefconfig`.
#
# Why the distinction matters: a plan that re-`--enable`s everything it cares
# about silently overrides edits made to `config`. A maintainer who turns
# something off in `config` sees the build succeed and the option still enabled,
# with nothing reported. Assertions make that contradiction a build failure
# instead of a silent veto, while still catching the real drift they were written
# for (upstream Kconfig dropping or re-gating a symbol during a version bump).
#
# Every function here is POSIX sh and returns non-zero on failure, so under the
# `/bin/sh -e` that wright uses for build stages the first missing symbol aborts
# the build.

# kassert_y <CONFIG_NAME>...
# Require each symbol to be exactly "y" in .config.
kassert_y() {
    _ay_bad=0
    for _ay_sym in "$@"; do
        if ! grep -qx "CONFIG_${_ay_sym}=y" .config; then
            echo "ERROR: CONFIG_${_ay_sym} is not set to y in the final .config." >&2
            echo "       Either the maintained baseline lost it, or upstream" >&2
            echo "       Kconfig re-gated it and it cannot be enabled this way." >&2
            _ay_bad=1
        fi
    done
    return ${_ay_bad}
}

# kassert_m <CONFIG_NAME>...
# Require each symbol to be exactly "m" in .config.
kassert_m() {
    _am_bad=0
    for _am_sym in "$@"; do
        if ! grep -qx "CONFIG_${_am_sym}=m" .config; then
            echo "ERROR: CONFIG_${_am_sym} is not set to m in the final .config." >&2
            _am_bad=1
        fi
    done
    return ${_am_bad}
}

# kassert_n <CONFIG_NAME>...
# Require each symbol to be absent or "is not set" in .config.
#
# Accepts a missing line on purpose: for a symbol that upstream removed, "not
# present" is a stronger statement than "not set", and asserting the old name
# forever would turn a successful cleanup into a permanent build failure.
kassert_n() {
    _an_bad=0
    for _an_sym in "$@"; do
        if grep -qx "CONFIG_${_an_sym}=[ym]" .config; then
            echo "ERROR: CONFIG_${_an_sym} is enabled in the final .config but must not be." >&2
            _an_bad=1
        fi
    done
    return ${_an_bad}
}

# kassert_str <CONFIG_NAME> <expected-with-quotes>
# Require a string symbol to hold an exact value, quotes included.
kassert_str() {
    _as_sym=$1
    _as_want=$2
    if ! grep -qx "CONFIG_${_as_sym}=${_as_want}" .config; then
        echo "ERROR: CONFIG_${_as_sym} expected value ${_as_want} in the final .config." >&2
        echo "       Found: $(grep -E "^CONFIG_${_as_sym}=" .config || echo '<absent>')" >&2
        return 1
    fi
    return 0
}

# kassert_val <CONFIG_NAME> <expected-number>
# Require an integer symbol to hold an exact value.
kassert_val() {
    _av_sym=$1
    _av_want=$2
    if ! grep -qx "CONFIG_${_av_sym}=${_av_want}" .config; then
        echo "ERROR: CONFIG_${_av_sym} expected value ${_av_want} in the final .config." >&2
        echo "       Found: $(grep -E "^CONFIG_${_av_sym}=" .config || echo '<absent>')" >&2
        return 1
    fi
    return 0
}
