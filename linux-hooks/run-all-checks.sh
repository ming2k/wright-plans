#!/bin/sh
# Run every offline check for the Theseus kernel plans.
#
# Usage: sh run-all-checks.sh [plans-root]
#
# This is the entry point a maintainer (or CI) runs before touching a kernel
# plan. It exists because the checks themselves are useless if nobody knows to
# run them: the repository had no test hook at all, so the boot-entry logic and
# the README/config agreement were verified exactly never.
#
# What runs:
#   1. shell syntax of every pipeline script and transaction hook
#   2. the kernel-hooks decision table (version sorting, boot counting, cross
#      kernel isolation, running-kernel guards)
#   3. the kconfig assertion helpers, including their failure paths
#   4. README claims vs the maintained config, for every kernel plan
#   5. plan lint, when the wright binary is available
#
# No root, no network, no kernel build.

set -u

HERE=$(dirname "$0")
ROOT=${1:-$(cd "${HERE}/.." && pwd)}
PLANS="${ROOT}"
HOOKS="${PLANS}/linux-hooks"

fails=0
section() { printf '\n== %s ==\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

section "shell syntax"
for plan in linux linux-lts linux-hooks; do
    [ -f "${PLANS}/${plan}/plan.toml" ] || continue
    python3 - "${PLANS}/${plan}/plan.toml" <<'PY' || fails=$((fails + 1))
import sys, tomllib, re, subprocess, tempfile, os
src = sys.argv[1]
d = tomllib.load(open(src, 'rb'))
bad = 0
scripts = []
for stage, cfg in d.get('pipeline', {}).items():
    if cfg.get('script'):
        scripts.append(f"{os.path.basename(os.path.dirname(src))}.{stage}")
        bodies = [(f"{os.path.basename(os.path.dirname(src))}.{stage}", cfg['script'])]
for i, out in enumerate(d.get('output', [])):
    for hk, hv in out.get('hooks', {}).items():
        scripts.append(f"{os.path.basename(os.path.dirname(src))}.{hk}")
# re-collect with bodies
bodies = []
for stage, cfg in d.get('pipeline', {}).items():
    if cfg.get('script'):
        bodies.append((f"pipeline.{stage}", cfg['script']))
for out in d.get('output', []):
    for hk, hv in out.get('hooks', {}).items():
        bodies.append((f"hooks.{hk}", hv))
for name, body in bodies:
    f = tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False)
    f.write(body); f.close()
    r = subprocess.run(['sh', '-n', f.name], capture_output=True, text=True)
    os.unlink(f.name)
    plan = os.path.basename(os.path.dirname(src))
    if r.returncode:
        print(f"  FAIL {plan}.{name}: {r.stderr.strip()}"); bad += 1
    else:
        print(f"  ok   {plan}.{name}")
sys.exit(1 if bad else 0)
PY
done

section "kernel-hooks decision table"
if [ -f "${HOOKS}/test-kernel-hooks.sh" ]; then
    sh "${HOOKS}/test-kernel-hooks.sh" > /tmp/.kh-test.$$ 2>&1 \
        && echo "  ok   $(grep -c '  ok ' /tmp/.kh-test.$$) case(s) passed" \
        || { bad "kernel-hooks tests"; sed 's/^/       /' /tmp/.kh-test.$$; }
    rm -f /tmp/.kh-test.$$
else
    bad "missing ${HOOKS}/test-kernel-hooks.sh"
fi

section "kconfig assertion helpers"
if [ -f "${HOOKS}/test-kconfig-assert.sh" ]; then
    sh "${HOOKS}/test-kconfig-assert.sh" > /tmp/.ka-test.$$ 2>&1 \
        && echo "  ok   $(grep -c '  ok ' /tmp/.ka-test.$$) case(s) passed" \
        || { bad "kconfig-assert tests"; sed 's/^/       /' /tmp/.ka-test.$$; }
    rm -f /tmp/.ka-test.$$
else
    bad "missing ${HOOKS}/test-kconfig-assert.sh"
fi

section "README vs config"
for plan in linux linux-lts; do
    [ -f "${PLANS}/${plan}/README.md" ] || { echo "  skip ${plan} (no README)"; continue; }
    if sh "${HOOKS}/check-readme-config.sh" "${PLANS}/${plan}" > /tmp/.rm-test.$$ 2>&1; then
        echo "  ok   ${plan}: $(grep -o 'checked [0-9]*' /tmp/.rm-test.$$)"
    else
        bad "${plan} README/config"
        sed 's/^/       /' /tmp/.rm-test.$$
    fi
    rm -f /tmp/.rm-test.$$
done

section "plan lint"
if command -v wright >/dev/null 2>&1; then
    if wright lint linux linux-lts linux-hooks > /tmp/.lint.$$ 2>&1; then
        echo "  ok   wright lint"
    else
        # lint needs write access to the wright state dir; report without failing
        if grep -q 'Permission denied' /tmp/.lint.$$; then
            echo "  skip wright lint (no write access to wright state dir)"
        else
            bad "wright lint"
            sed 's/^/       /' /tmp/.lint.$$
        fi
    fi
    rm -f /tmp/.lint.$$
else
    echo "  skip (wright not in PATH)"
fi

printf '\n'
if [ "${fails}" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
    exit 0
fi
echo "${fails} CHECK(S) FAILED"
exit 1
