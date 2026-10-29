# Theseus Linux Kernel Configuration

A modern, streamlined Linux kernel configuration targeting contemporary x86-64 hardware (x86-64-v3 baseline with AVX2/BMI2/FMA).

## Philosophy

**Modern-First**: We optimize for hardware from the last ~10 years. Legacy compatibility is intentionally dropped to reduce attack surface, build time, and kernel image size.

**Security by Default**: All available CPU mitigations are enabled, modules are signed, and Rust support is included for future memory-safe drivers.

**Performance**: Aggressive optimizations inspired by CachyOS while maintaining stability.

## Target Hardware

- **CPU**: Intel Haswell+ / AMD Zen+ (x86-64-v3 baseline)
  - Unsupported: Centaur, Zhaoxin, Hygon, pre-2013 Intel/AMD
- **Storage**: NVMe, AHCI/SATA (legacy PATA controllers removed)
- **USB**: XHCI (USB 3.x) only; OHCI/UHCI removed
  - USB 1.1/2.0 devices still work via XHCI internal hub emulation
- **Graphics**: Intel i915/Xe, AMD DRM; legacy framebuffer drivers removed
- **Audio**: Intel HDA + SOF (Sound Open Firmware)
- **Thunderbolt**: Intel Thunderbolt 4/USB4
- **Network**: Modern Ethernet, Wi-Fi 6/7 (nl80211 only, no WEXT)

## Key Differences from Arch Linux

| Feature | Arch Linux | Theseus |
|---------|-----------|---------|
| x86-64 version | v1 (baseline) | **v3** (AVX2/BMI2/FMA) |
| CPU vendors | All (incl. Centaur/Zhaoxin) | Intel/AMD only |
| Preempt | Standard | **Dynamic preempt** |
| eBPF schedulers | No | **SCHED_CLASS_EXT** |
| Rust support | Optional | **Enabled** |
| Module compression | Partial | **All modules** |
| CFS base slice | Default | **1.6ms** (reduced context switching) |
| Legacy virtual guests | Xen, Jailhouse, ACRN, Bhyve | **KVM only** |
| Amateur radio | AX25 stack | **Removed** |
| USB 1.1 controllers | OHCI/UHCI | **Removed** |
| Debug options | Extensive | **Minimized** |

## Optimizations Borrowed from CachyOS

- `CONFIG_SCHED_CLASS_EXT=y` — eBPF scheduler extensibility (scx-scheds)
- `CONFIG_MODULE_COMPRESS_ALL=y` — Compressed modules reduce `/lib/modules` size
- `CONFIG_HZ=1000` — Low latency timer ticks (CachyOS uses 300, we keep 1000 for responsiveness)
- Debug minimization — `DEBUG_MISC`, `RCU_TRACE` and `X86_DEBUG_FPU` are
  explicitly disabled even though `DEBUG_KERNEL` is on, because `DEBUG_KERNEL` is
  required to reach the BTF choice. `DEBUG_KERNEL` itself is *not* disabled: doing
  so would also remove BTF, which the eBPF CO-RE section below depends on. Those
  three carry real runtime cost — upstream's own help text for `X86_DEBUG_FPU`
  says it "adds some small amount of runtime overhead" — and `DEBUG_KERNEL`
  enables them by default, so naming them explicitly is what keeps them off.

## Gaming & Creative Input

- **Gamepads**: Xbox (xpad), PlayStation DualShock (hid-sony), Nintendo, Steam Controller
- **Tablets**: Wacom USB HID, serial Wacom
- **HID**: Logitech (incl. Unifying), Microsoft, Apple, Lenovo, and generic USB HID

## Removed / Unsupported

- Amateur radio protocols (AX25, NETROM, ROSE)
- Legacy ISA/PCI bus devices
- Pre-2013 CPU-specific drivers (PowerNow K8, P4 Clockmod, Speedstep)
- Legacy virtual machine guests (Xen domU, Jailhouse, ACRN, Bhyve)
- Legacy SATA/PATA controllers (Silicon Image, SiS, VIA, ULi, etc.)
- Legacy framebuffer drivers (Cirrus, S3, Matrox, etc.)
- Old serial ports (Exar, MEN, PCI1xxxx)
- Most USB-to-serial adapters (except common FTDI/CP210x/CH340)
- PCMCIA, PC Card, EISA, MCA bus support

## Compiler Optimizations

- `CONFIG_LTO_NONE=y` — no Link Time Optimization.
  - ThinLTO was evaluated for a smaller image and cross-module optimisation, but
    is not enabled in the maintained baseline; the Clang ThinLTO symbols are not
    present in `config` at all.
  - If it is ever turned on, note that LTO roughly doubles build time and needs a
    Clang/LLVM toolchain, whereas this plan builds with GCC.

## eBPF Type Information (BTF)

BTF is enabled so that eBPF CO-RE programs — `dae`, `bpftrace`, and sched_ext
(`scx`) schedulers — can resolve kernel structure layouts at load time instead
of being rebuilt per kernel. The kernel exposes the data at
`/sys/kernel/btf/vmlinux`, backed by the vmlinux `.BTF` section
(`kernel/bpf/sysfs_btf.c` reads `__start_BTF`..`__stop_BTF`).

This requires three settings that depend on each other:

| Symbol | Why it is required |
| --- | --- |
| `CONFIG_DEBUG_KERNEL=y` | Un-hides the "Debug information" choice; BTF is nested under it |
| `CONFIG_DEBUG_INFO_BTF=y` | Generates the `.BTF` section from DWARF |
| `CONFIG_DEBUG_INFO_BTF_MODULES=y` | Per-module BTF, needed for module-side CO-RE |

`CONFIG_SCHED_CLASS_EXT` is enabled alongside them because Kconfig declares
`depends on BPF_SYSCALL && BPF_JIT && DEBUG_INFO_BTF`; it was documented as a
feature but could never actually be selected while BTF was off.

### pahole is a hard build dependency

Kbuild shells out to `pahole` (from the `dwarves` package) to convert DWARF into
BTF, and Kconfig gates BTF on `PAHOLE_VERSION >= 122`, probed at configure time
from `pahole --version`. **When `pahole` is absent, `make olddefconfig` silently
drops `DEBUG_INFO_BTF` and no diagnostic is printed** — the resulting kernel
simply has no `/sys/kernel/btf`. `plan.toml` therefore declares
`build_deps = ['dwarves']` and asserts the pahole version in `prepare`, so that
failure is loud rather than a silent downgrade.

### Modules are stripped, BTF is kept

`DEBUG_INFO=y` makes the installed module tree grow to roughly 900M. Staging
passes `INSTALL_MOD_STRIP=1`, which maps to `strip --strip-debug`: `.debug_*`
sections are removed while `.BTF` is retained. Module signing still succeeds
because `modules_install` signs after stripping. Measured on 6.18.59 for the
sibling LTS plan: ~74M with `.BTF` intact and PKCS#7 signatures present.

## Boot entry management

The hooks source `/usr/share/linux/kernel-hooks.sh`, shipped directly by this
package. Neither kernel package depends on the other, and their installed files
are completely disjoint (zero file conflicts, zero diversions).

Each hook sets two variables before sourcing:

```sh
LINUX_LOCALVERSION="-theseus"           # must match this plan's LOCALVERSION
LINUX_IMAGE="/boot/vmlinuz-theseus"
```

The library anchors its module glob and its boot-entry regex on
`LINUX_LOCALVERSION`, which is what keeps `linux` and `linux-lts` from
registering or pruning each other's entries. `-theseus` is a prefix of
`-theseus-lts`, so the distinction has to be explicit.

`post_upgrade` runs `prune_retired_kernels`, enforcing the active Keep-1 policy:
the newly registered kernel and the currently running kernel (`uname -r`) are
protected; all older versions of this series are pruned from ESP and `/usr/lib/modules/`.

## Testing

Run the self-contained offline test suite:

```bash
sh check.sh
```

It verifies pipeline shell syntax (`sh -n`), exercises the `kernel-hooks.sh`
Keep-1 decision table (20+ cases), verifies the `kconfig-assert.sh` helpers (12
cases), and validates this document's `CONFIG_` claims against `config`.

## Security Features

- `CONFIG_STACKPROTECTOR_STRONG=y`
- `CONFIG_X86_CET=y` + `CONFIG_X86_KERNEL_IBT=y`
- `CONFIG_RANDOMIZE_BASE=y` + `CONFIG_RANDOMIZE_MEMORY=y`
- `CONFIG_MODULE_SIG=y` + `CONFIG_MODULE_SIG_ALL=y` (SHA-512)
- `CONFIG_SECCOMP=y` + `CONFIG_SECCOMP_FILTER=y`
- `CONFIG_MODIFY_LDT_SYSCALL` is not set — requires `CONFIG_EXPERT=y` to be
  reachable at all, see the "Expert-gated hardening" block in `plan.toml`

Deliberately **not** enabled, despite being common distro defaults:

- **`CONFIG_RUST`** — the toolchain symbols (`CONFIG_RUSTC_VERSION` etc.) appear
  in `config` because Kconfig probes the compiler, but Rust support itself is not
  selected, so no in-tree Rust driver is built.
- **`CONFIG_SECURITY_APPARMOR`** — AppArmor is not the LSM in use here.
- **ThinLTO** — disabled; see the Compiler Optimizations section above.

## How to Customize

The canonical configuration lives in `config`. Edit it directly for feature changes:

```bash
make menuconfig
```

The `plan.toml` prepare script starts from `config`, runs `make olddefconfig`, applies its `scripts/config` entries, and runs `make olddefconfig` again. The final build `.config` is what gets installed as `/boot/config-theseus`.

Note that `plan.toml` currently carries 109 `scripts/config` entries. Per the
policy below, most of them are **guardrails**, not preferences: upstream Kconfig
symbols around SOF, SPI and the Intel NPU are renamed or re-gated often enough
that `olddefconfig` can drop them silently, so they are re-asserted on every
build on purpose. The count is high by design; it is not a leftover to prune
wholesale. What matters is that each block names the symbol, the reason, and the
runtime scenario it protects.

## Config Maintenance Policy

`config` is the maintained baseline and should carry normal feature choices. If you enable or disable ordinary hardware support, drivers, filesystems, or debug options, prefer updating `config` and keeping the policy visible there.

`plan.toml` should stay small. It is reserved for two explicit categories:

- **Guardrail**: a build-time assertion that intentionally runs every build to prevent silent breakage when the baseline `config` or upstream Kconfig symbols drift. Examples: boot filesystems, NVMe, UEFI, systemd hard requirements, module signing, nl80211-only wireless policy, and Intel SOF/DMIC audio support.
- **Baseline sync**: a temporary one-time migration aid. Use this when changing a cluster of options during an upgrade or hardware-support pass. After a verified build, copy the final build `.config` back to `linux/config`, confirm those options are present, then remove the matching `Baseline sync` block from `plan.toml`.

Practical workflow after a kernel upgrade:

```bash
# Inside the kernel build directory, after the second olddefconfig has run:
cp .config /var/lib/wright/plans/linux/config
```

Then inspect `plan.toml`:

- Keep `Guardrail` blocks if losing that setting would make the system unbootable, break required userspace, or repeat a known Kconfig drift bug.
- Remove `Baseline sync` blocks once their settings are present in `config` and the rebuilt kernel has been tested.
- Do not add long-lived `scripts/config` lines for normal preferences; put those in `config`.

This keeps the baseline readable while still protecting the build from high-impact regressions like dropping SOF modules and losing internal digital microphones.

## License

GPL-2.0-only, same as upstream Linux.
