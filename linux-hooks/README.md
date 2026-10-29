# linux-hooks

Shared boot-entry helpers and build-time Kconfig assertion helpers for Theseus
kernel plans (`linux`, `linux-lts`).

This package ships two libraries:
- `/usr/share/linux/kernel-hooks.sh` — transaction hook helpers (register, Keep-1 active prune, remove)
- `/usr/share/linux/kconfig-assert.sh` — build-time Kconfig assertion helpers (SET vs ASSERT)

## Why a separate plan

Both kernel plans need identical boot-entry logic: resolve the installed
`KERNELRELEASE`, hand it to `kernel-install`, retire old versions under a
Keep-1 policy, and never touch the running kernel's entry. Before this plan
existed, `linux` carried that logic in an installed library while `linux-lts`
inlined a divergent copy, and the copies drifted apart in ways that mattered:

| Behaviour | `linux` (library) | `linux-lts` (inlined, before) | `linux-hooks` (now) |
| --- | --- | --- | --- |
| Version ordering | `sort -V` | plain `sort` (`6.18.9` ranks above `6.18.10`) | `sort -V` |
| `kernel-install` failure | propagated | swallowed by `\|\| true` | propagated |
| Running-kernel entry on removal | protected | **removed** | **protected** |
| Kernel naming | derived from module dir | `${VERSION}` fallback | derived from module dir |
| Cleanup policy | passive orphan scan | passive orphan scan | **active Keep-1 (reclaim disk & ESP)** |

Keeping one implementation is what makes those fixes reach both kernels instead
of one.

## Why the kernel plans do not depend on each other

`linux-lts` must not source a library installed by `linux`. If it did, removing
`linux` would break LTS kernel upgrades, and installing `linux` would silently
change LTS behaviour. The dependency therefore points the other way: both kernel
plans list `linux-hooks` in:
- `build_deps` — supplies `/usr/share/linux/kconfig-assert.sh` at build time
- `runtime_deps` — supplies `/usr/share/linux/kernel-hooks.sh` at install/upgrade/remove time

Neither kernel depends on the other.

## How kernels stay separated

The library takes the kernel suffix as a parameter, `LINUX_LOCALVERSION`, and
anchors **both** its module-directory glob and its boot-entry regex on it:

```sh
LINUX_LOCALVERSION="-theseus-lts"
LINUX_IMAGE="/boot/vmlinuz-theseus-lts"
. /usr/share/linux/kernel-hooks.sh
require_kernel_install
register_kernel
prune_retired_kernels
```

This anchoring is not cosmetic. `-theseus` is a **prefix** of `-theseus-lts`, so
any prefix-based match in either direction would let one kernel claim, register
or prune the other's boot entry. Both directions are covered by tests.

## Active Keep-1 Policy (`prune_retired_kernels`)

Traditional passive orphan cleanup only deletes an ESP boot entry if its module
directory `/usr/lib/modules/<version>` is already gone from disk. If an old
directory remains (due to pre-existing system state, failed transaction, or
untracked files), passive cleanup refuses to delete the UKI entry, allowing dead
entries to accumulate forever.

`prune_retired_kernels` actively enforces the Keep-1 invariant:
1. Target version (`_pr_target`, freshly registered newest kernel) is protected.
2. Running version (`_pr_running = uname -r`) is protected.
3. Every older version of the same `LINUX_LOCALVERSION`:
   - Its UKI / BLS boot entry is removed from ESP via `kernel-install remove`
   - Its retired module tree under `/usr/lib/modules/` is removed

This automatically converges the system to **exactly 1 LTS and 1 default kernel**
without manual intervention.

## No hook reads `${VERSION}`

The plan version is not the kernel release, and must never be used to synthesise
a module directory name:

- plan version `6.18.59` -> kernel release `6.18.59-theseus-lts`
- a plan version without a sublevel (e.g. `6.18`) -> `6.18-theseus-lts`, which
  does not exist, since the release always carries the full sublevel

Only the installed module directory can name a kernel.

## Testing

The library is written so that every path is redirectable through a
`${VAR:-default}` knob, which makes the entire decision table testable offline —
no root, no real `/boot`, no kernel build:

```sh
sh test-kernel-hooks.sh        # 28 cases: sorting, parsing, Keep-1 active pruning, isolation
sh test-kconfig-assert.sh      # 15 cases: kassert helpers, negative failures, sh -e aborts
sh check-readme-config.sh ..   # README vs config symbol verification
sh run-all-checks.sh           # full test suite entry point
```

## Adding a kernel plan

1. Declare `build_deps = ['dwarves', 'linux-hooks']` and `runtime_deps = [..., 'linux-hooks']`.
2. Set `LINUX_LOCALVERSION` to the plan's `LOCALVERSION` and `LINUX_IMAGE` to its
   installed image path in every hook.
3. Source `/usr/share/linux/kernel-hooks.sh` unconditionally in hooks.
4. Source `/usr/share/linux/kconfig-assert.sh` in prepare stage.
5. Call `require_kernel_install`, then `register_kernel` / `prune_retired_kernels` /
   `remove_kernel`.
6. Extend `test-kernel-hooks.sh` with the new suffix so cross-kernel isolation
   stays covered.
