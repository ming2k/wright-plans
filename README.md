# Plan Repository Guidelines

## Incident Report: OpenSSL 4.0.0 Upgrade (2026-05-07)

### What Happened

Upgrading `openssl` from `3.6.2` to `4.0.0` broke the entire system because:

- OpenSSL 4.0.0 bumped the shared library soname from `libcrypto.so.3` / `libssl.so.3` to `.so.4`.
- All installed binaries (sudo, su, pkexec, hostnamectl, python, etc.) were still dynamically linked against the old `.so.3`.
- After the upgrade, every one of these binaries failed with:
  ```
  error while loading shared libraries: libcrypto.so.3: cannot open shared object file
  ```
- Recovery required manually extracting the previous wright package archive from `/var/lib/wright/parts/`.

### Root Causes

1. **Soname/ABI break unnoticed**: OpenSSL 4.x is a major version that changes the shared-library soname. This is not a drop-in replacement.
2. **No reverse-dependency rebuild**: Wright applied the new OpenSSL but did not rebuild (or schedule a rebuild of) every package linked against it.
3. **No rollback path**: Once the new package was installed, there was no quick way to revert without a pre-staged archive.
4. **Lack of upgrade staging**: The plan was updated and applied directly on the production/development host without testing in isolation.

### Lessons Learned

- **Shared-library soname bumps are system-breaking events**, not routine patch updates.
- Core libraries (openssl, glibc, gcc, libxcrypt) must be treated with extreme caution.
- Always assume that a major version upgrade of a core library requires a full-system rebuild or, at minimum, backward-compatible symlinks and a phased rollout.

## Core Library Upgrade Policy

For packages that provide base shared libraries used by the toolchain, init system, or privilege-escalation binaries (`sudo`, `su`, `pkexec`), adhere to the following:

### 1. Prefer Conservative Versions

Stay on the latest **stable maintenance branch** rather than the newest major release unless there is a compelling security or feature requirement.

| Package | Current Safe Branch | Notes |
|---------|---------------------|-------|
| openssl | 3.6.x | 4.0.x changes soname; avoid until full ecosystem rebuild is planned |
| glibc   | 2.4x  | Upgrades often require full-system rebuild |
| gcc     | 14.x  | libstdc++ soname changes are rare but possible |

### 2. Check for Soname Changes Before Bumping

Before updating the version in a core library plan, verify whether the new release changes `SONAME`:

```bash
readelf -d /usr/lib/libfoo.so | grep SONAME
```

If the soname changes, treat the upgrade as a **breaking change**.

### 3. Rebuild Reverse Dependencies

After installing a new core library, rebuild all dependent packages:

```bash
wright rebuild --reverse-deps openssl
```

If wright does not support automatic reverse-dependency rebuilds, maintain a manual list of affected packages.

### 4. Provide Backward-Compatible Symlinks (if ABI-compatible)

If the new major version maintains ABI compatibility but changes the soname, consider adding compatibility symlinks in the plan's staging script:

```bash
ln -sf libfoo.so.NEW ${STAGING_DIR}/usr/lib/libfoo.so.OLD
```

> **Caution**: Only do this if upstream explicitly guarantees ABI compatibility. Otherwise, subtle runtime crashes may occur.

### 5. Test in Isolation

Never apply a core library upgrade directly to the host you are working on without a recovery path. Prefer:

- A container/VM snapshot
- A secondary build host
- A chroot environment

### 6. Keep Previous Package Archives

Wright keeps built packages in `/var/lib/wright/parts/`. Do not delete the previous version archive of a core library until you have confirmed the new version works and all dependents are rebuilt.

### 7. Document Breaking Changes in Plan Comments

If a plan must track a new major version, add a prominent comment:

```toml
# WARNING: This version bumps libcrypto soname from .3 to .4.
# Do not apply until all reverse dependencies are rebuilt.
version = "4.0.0"
```

## Suggested Actions After This Incident

1. **Audit all current plans** for other core libraries that might be close to a major version bump.
2. **Implement a pre-apply hook** (or manual checklist) for plans tagged as `core-library`.
3. **Add reverse-dependency tracking** to wright if not already present, so `wright apply openssl` automatically schedules rebuilds of dependent packages.
4. **Pin core libraries** to LTS branches by default; create separate `-next` plans for major-version testing.
