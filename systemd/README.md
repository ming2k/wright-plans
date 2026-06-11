# systemd

## Version: 260.2

System and Service Manager for Theseus Linux. This plan carries more
machine-specific policy than most plans, so the decisions are recorded here.

## Files in this plan

| File | Purpose |
|------|---------|
| `plan.toml` | Main plan (full build: cryptsetup, TPM2, PAM, …) |
| `mvp.toml` | Minimal bootstrap variant (no cryptsetup/tpm2-tss) |
| `80-theseus.preset` | Service preset installed to `/usr/lib/systemd/system-preset/` |
| `network-wait-online.conf` | Drop-in for `systemd-networkd-wait-online.service` |

## Service presets

Preset files are pure policy — something must apply them. There are two
paths, and only these two:

- **Fresh root (`wright launch`)**: plan hooks do not run during launch, so
  nothing presets in the chroot. Instead PID 1 applies `preset-all` itself on
  the first boot, triggered by an uninitialized `/etc/machine-id`. By default
  that pass is *enable-only*; `-D first-boot-full-preset=true` in this plan
  makes it apply `disable` rules too, so the full policy lands without any
  hook.
- **Live system**: the first-boot trigger never fires again, so each plan
  that ships units must run `systemctl preset <its units>` in its
  `post_install` (e.g. the greetd plan presets `greetd.service` and
  `getty@tty1.service`). This plan's own `post_install` runs
  `systemd-machine-id-setup` + `preset-all` for the bootstrap-by-install
  case. Never preset in `post_upgrade` — admin enablement state must survive
  upgrades.

Two rules of the preset mechanism shape everything here:

- Files are processed in **lexical order** and the **first matching rule
  wins**. Upstream ships `90-systemd.preset`, so Theseus policy must sort
  earlier — hence `80-theseus.preset`. The `00-49` range is left free for
  ad-hoc admin overrides in `/etc/systemd/system-preset/`.
- A unit that matches **no** rule at all is **enabled** by default, so
  leaving a unit out of the preset does not keep it off — it needs an
  explicit `disable` line, or `preset-all` re-enables it on the next
  rebuild/upgrade. (`systemd-pcrlock-make-policy.service` is disabled for
  exactly this reason; see below.)

Preset files are split by responsibility: this plan ships base-OS policy
(`80-theseus.preset`); the greetd plan ships display/login policy
(`85-display-manager.preset`: `enable greetd`, `disable getty@` — greetd
owns VT1, logind autovt spawns getty on tty2+ on demand).

## TPM2 LUKS unlock: PIN-only, no PCRs, no pcrlock

This machine dual-boots Windows. Windows Update rewrites Secure Boot NVRAM
state (dbx revocation lists, the UEFI CA 2023 certificate rollout) and ships
Lenovo firmware capsules — any of which changes PCR 7 (and can drift PCR
0/1/2). A PCR-bound LUKS enrollment then fails before the PIN is even
evaluated. Windows reseals its own BitLocker around such updates; nothing
reseals the LUKS binding. pcrlock cannot predict Windows-initiated dbx
changes either, and its stale policy broke enrollments here once already.

Decision: bind the root LUKS enrollment to a **PIN only**. Theft protection
still holds (the key never leaves the TPM; anti-hammering throttles PIN
brute force). The trade-off is no boot-chain attestation (evil-maid),
accepted for a single-user workstation. A PCR 11 signed policy
(`--tpm2-public-key`) is the planned upgrade once the UKI build signs PCR
predictions into a `.pcrsig` section.

### Canonical enrollment

```sh
systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto \
    --tpm2-pcrs="" --tpm2-with-pin=yes --tpm2-pcrlock="" /dev/nvme1n1p2
```

`--tpm2-pcrlock=""` is **mandatory**: if `/var/lib/systemd/pcrlock.json`
exists, systemd-cryptenroll silently binds the new token to it, and the
token will never unseal at boot ("No pcrlock policy found among system
credentials"). That file is produced by `systemd-pcrlock-make-policy.service`
— which is why the preset disables it.

### Verifying an enrollment

`cryptsetup luksDump /dev/nvme1n1p2`, under `Tokens: systemd-tpm2`:

| Field | Expected |
|-------|----------|
| `tpm2-hash-pcrs` | empty |
| `tpm2-pin` | `true` |
| `tpm2-pcrlock` | `false` |
| `tpm2-pcrlock-nv` | `false` |

### Recovery when unlock breaks

1. Boot with the LUKS passphrase (keep that key slot forever).
2. Check the failure: `journalctl -b -u 'systemd-cryptsetup*'`.
   - "TPM policy does not match current system state" → PCR/policy drift.
   - "No pcrlock policy found among system credentials" → token was
     enrolled against pcrlock.json; remove it:
     `/usr/lib/systemd/systemd-pcrlock remove-policy`
     (full path — not in `$PATH`).
3. Re-run the canonical enrollment above, verify, reboot.

`/etc/crypttab` options (`tpm2-device=auto,discard`) only tell
systemd-cryptsetup to *try* TPM2; the actual binding parameters live in the
LUKS2 token metadata, not in crypttab. A `tpm2-pcrs=` crypttab option is
ignored for enrolled tokens. crypttab changes need an initrd rebuild.

## Console login chain

```
greetd (VT1) → agreety → niri-session
tty2–tty6                  getty spawned on demand by logind autovt
                           (NAutoVTs=6 default; nothing preset-enabled)
```

### Known issue: boot log noise on the greeter

Two causes:

1. `getty@tty1.service` fights greetd over VT1 (upstream
   `90-systemd.preset` enables it via `DefaultInstance=tty1`). Fixed in
   plans by the greetd plan's `85-display-manager.preset`, applied by its
   `post_install`; on an already installed system, run
   `systemctl disable getty@tty1.service` once (upgrades deliberately do
   not preset).
2. **Still open**: the kernel command line has no `quiet`/`loglevel=`, so
   kernel and systemd messages land on tty1 and interleave with the
   agreety prompt. Fix by adding `quiet loglevel=3` to the UKI cmdline in
   the kernel plan.
