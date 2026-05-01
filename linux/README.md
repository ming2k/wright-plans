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
- `CONFIG_MIN_BASE_SLICE_NS=1600000` — Reduced CFS scheduling overhead
- `CONFIG_MODULE_COMPRESS_ALL=y` — Compressed modules reduce `/lib/modules` size
- `CONFIG_HZ=1000` — Low latency timer ticks (CachyOS uses 300, we keep 1000 for responsiveness)
- Debug minimization — Disabled DEBUG_KERNEL, DEBUG_WX, DEBUG_SHIRQ, etc.

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

- `CONFIG_LTO_CLANG_THIN=y` — Link Time Optimization (Clang ThinLTO)
  - Reduces binary size and improves performance via cross-module optimization
  - Build time increase: ~20-40% (much faster than Full LTO)

## Security Features

- `CONFIG_STACKPROTECTOR_STRONG=y`
- `CONFIG_RETPOLINE=y` + all Spectre/Meltdown mitigations
- `CONFIG_CET=y` + `CONFIG_X86_KERNEL_IBT=y`
- `CONFIG_RANDOMIZE_BASE=y` + `CONFIG_RANDOMIZE_MEMORY=y`
- `CONFIG_MODULE_SIG=y` + `CONFIG_MODULE_SIG_ALL=y` (SHA-512)
- `CONFIG_RUST=y` — Foundation for memory-safe driver development
- `CONFIG_SECCOMP=y` + `CONFIG_SECCOMP_FILTER=y`
- AppArmor support enabled

## How to Customize

The canonical configuration lives in `config`. Edit it directly for feature changes:

```bash
make menuconfig
```

The `plan.toml` prepare script starts from `config`, runs `make olddefconfig`, applies a small set of `scripts/config` assertions, and runs `make olddefconfig` again. The final build `.config` is what gets installed as `/boot/config-theseus`.

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
