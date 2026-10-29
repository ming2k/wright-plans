# Theseus Linux LTS Kernel Configuration

The long-term-support kernel, and the one actually deployed: `folios/base.toml`
installs `linux-lts`, while the rolling `linux` plan is not part of any folio.
That makes everything below the default experience on a Theseus machine.

## Relationship to the `linux` plan

`linux-lts` tracks the newest kernel.org `longterm` branch and shares its
philosophy with `linux`: modern x86-64 hardware only, no 32-bit userspace, eBPF
CO-RE enabled. The two plans differ only where an LTS kernel genuinely requires
it, so where this document is silent, `linux/README.md` applies.

Concrete differences:

| Aspect | `linux` (rolling) | `linux-lts` |
| --- | --- | --- |
| Kernel branch | newest mainline/stable | newest `longterm` |
| `LOCALVERSION` | `-theseus` | `-theseus-lts` |
| Kernel image | `/boot/vmlinuz-theseus` | `/boot/vmlinuz-theseus-lts` |
| Deployed by a folio | no | **yes** (`base.toml`) |
| BTF / `CONFIG_SCHED_CLASS_EXT` | enabled | enabled |

## eBPF Type Information (BTF)

BTF is what lets eBPF CO-RE programs — `dae`, `bpftrace`, sched_ext (`scx`)
schedulers — resolve kernel structure layouts at load time instead of being
rebuilt per kernel. The kernel exposes it at `/sys/kernel/btf/vmlinux`, backed by
the vmlinux `.BTF` section.

Because `linux-lts` is the deployed kernel, BTF being off here means those tools
break on every installed system. Before this configuration was aligned, that was
exactly the state: the shipped 6.18.44 kernel had `CONFIG_DEBUG_KERNEL` unset and
therefore no `/sys/kernel/btf` at all.

Four settings have to line up, and **missing any one of them fails silently**:

| Symbol | Why it is required |
| --- | --- |
| `CONFIG_DEBUG_KERNEL` | un-hides the "Debug information" choice; BTF is nested under it |
| `CONFIG_DEBUG_INFO_DWARF5` | supplies the DWARF that pahole converts |
| `CONFIG_DEBUG_INFO_BTF` | generates the vmlinux `.BTF` section |
| `CONFIG_DEBUG_INFO_BTF_MODULES` | per-module BTF, needed for module-side CO-RE |

`CONFIG_SCHED_CLASS_EXT` is asserted alongside them because Kconfig declares
`depends on BPF_SYSCALL && BPF_JIT && DEBUG_INFO_BTF`, so it can only be enabled
while BTF is on.

### pahole is a hard build dependency

Kbuild shells out to `pahole` (from `dwarves`) to convert DWARF into BTF, and
Kconfig gates BTF on `CONFIG_PAHOLE_VERSION`, probed from `pahole --version` at
configure time. **When pahole is absent, `olddefconfig` silently drops
`CONFIG_DEBUG_INFO_BTF` and prints nothing.** The plan therefore declares
`build_deps = ['dwarves']`, runs `prepare` with `isolation = "none"` so pahole is
visible at probe time, and asserts both the pahole version and the resulting
symbols so the downgrade becomes a build failure.

Threshold note: 6.18 gates BTF on `CONFIG_PAHOLE_VERSION >= 116` plus
(`DEBUG_INFO_DWARF4` || `CONFIG_PAHOLE_VERSION >= 121`), which is laxer than the 122
that 7.3 requires. The plan asserts 122 in both cases on purpose: the shipped
`dwarves` provides 1.32, so the stricter bound never rejects a valid build, and
it keeps both kernel plans asserting one invariant.

### Modules are stripped, BTF is kept

`DEBUG_INFO=y` grows the installed module tree to roughly 900M. Staging passes
`INSTALL_MOD_STRIP=1`, which maps to `strip --strip-debug`: `.debug_*` sections
are removed while `.BTF` is retained. Measured on 6.18.59: ~74M with `.BTF`
intact, and module signatures still present because `modules_install` signs after
stripping. Verified directly with `readelf -S`: zero `.debug_*` sections remain,
`.BTF` and the PKCS#7 signature do.

## Expert-gated hardening

`CONFIG_MODIFY_LDT_SYSCALL` is declared `bool ... if EXPERT`. With `EXPERT` off the
prompt is hidden and Kconfig keeps `default y`, so a bare
`scripts/config --disable MODIFY_LDT_SYSCALL` is **silently ignored** — which is
why the shipped 6.18.44 kernel still exposed `modify_ldt(2)` despite the plan
asking for it to be off. The plan now enables `EXPERT` first, disables the
syscall, and asserts it is gone.

`EXPERT` carries `select DEBUG_KERNEL` ("Unhide debug options"), and
`CONFIG_DEBUG_KERNEL` has several `default y` children with real runtime cost.
Measured with `olddefconfig` on 6.18.59, `EXPERT` alone turns on `CONFIG_X86_DEBUG_FPU`,
`CONFIG_RCU_TRACE` and `CONFIG_DEBUG_MISC`, so the plan disables those three explicitly.

Side effect to re-check after any version bump: `MEDIA_HIDE_ANCILLARY_SUBDRV` is
`default y if MEDIA_SUBDRV_AUTOSELECT && !EXPERT`, so with `CONFIG_EXPERT` on it
disappears from the resulting `.config` (it is a promptless helper, so it is
simply not emitted) and a block of media I2C tuner/demod prompts becomes visible
again, each falling back to its own default. `X86_16BIT` and `X86_ESPFIX64` also
disappear for the same structural reason: both are
`default y ... depends on MODIFY_LDT_SYSCALL`. None of the three is something to
re-add; the point is only that the diff after an upgrade is larger than the two
LDT-related symbols.

## Config maintenance policy

`config` is the single source of truth for feature choices. Edit it directly for
ordinary hardware support, drivers, filesystems and debug options; the resulting
policy then lives in one readable file.

`plan.toml` deliberately does **not** re-apply those choices. Its `prepare` stage
does two distinct things, and the split is the point:

- **SET** (`scripts/config`) — only for values that cannot come from the shared
  baseline: per-plan identity (`LOCALVERSION`, `CONFIG_DEFAULT_HOSTNAME`), a
  build-host-independent floor (`CONFIG_X86_MINIMUM_CPU_FAMILY`), and derived symbols
  Kconfig computes from an already-disabled parent (`COMPAT*`, which in 6.18 are
  `def_bool` off the disabled `CONFIG_IA32_EMULATION` and no longer appear in `config`).
- **ASSERT** (`kassert_y` / `kassert_m` / `kassert_n`) — everything else. These
  require the value `config` already carries and abort the build when it did not
  survive `olddefconfig`, but they never write.

The distinction matters. Previously every option was re-applied with
`scripts/config --enable`, so 105 of 109 entries merely restated `config` and any
edit made to `config` was silently vetoed by the plan: the build succeeded and
the option stayed on. With assertions, a maintainer's edit either takes effect or
produces an explicit error naming the symbol.

Practical workflow after a kernel upgrade:

```bash
# Inside the kernel build directory, after the final olddefconfig has run:
cp .config /var/lib/wright/plans/linux-lts/config
sh check.sh
```

## Boot entry management

The hooks source `/usr/share/linux-lts/kernel-hooks.sh`, shipped directly by this
package in its own `/usr/share/linux-lts/` namespace. Neither kernel package
depends on the other, and their installed files are completely disjoint (zero
file conflicts, zero diversions).

Each hook sets two variables before sourcing:

```sh
LINUX_LOCALVERSION="-theseus-lts"      # must match this plan's LOCALVERSION
LINUX_IMAGE="/boot/vmlinuz-theseus-lts"
```

The library anchors its module glob and its boot-entry regex on
`LINUX_LOCALVERSION`. That anchoring is load-bearing: `-theseus` is a **prefix**
of `-theseus-lts`, so a prefix-based match in either direction would let one
kernel claim, register or prune the other's boot entry. Both directions are
covered by tests.

`post_upgrade` runs `prune_retired_kernels`, enforcing the active Keep-1 policy:
the newly registered kernel and the currently running kernel (`uname -r`) are
protected; all older versions of this series are pruned from ESP and `/usr/lib/modules/`.

No hook reads `${VERSION}`. The plan version is not the kernel release — plan
`6.18.59` is release `6.18.59-theseus-lts` — and for a plan whose version omits
the sublevel they diverge outright, so only the installed module directory can
name a kernel.

Behaviour inherited from the helper, all previously wrong here:

- a failed `kernel-install` now aborts instead of being swallowed by `|| true`
- `pre_remove` refuses to delete the **running** kernel's boot entry
- version ordering uses `sort -V`, so `6.18.10` is correctly newer than `6.18.9`

## Testing

Run the self-contained offline test suite:

```bash
sh check.sh
```

It verifies pipeline shell syntax (`sh -n`), exercises the `kernel-hooks.sh`
Keep-1 decision table (20+ cases), verifies the `kconfig-assert.sh` helpers (12
cases), and validates this document's `CONFIG_` claims against `config`.


The hook and assertion suites run fully offline: no root, no real `/boot`, no
kernel build. Every path is redirectable through a `${VAR:-default}` knob and
`kernel-install` is stubbed.

## License

GPL-2.0-only, same as upstream Linux.
