# libva

## Version: 2.2.0

### Build Hierarchy (Layer 2)
1. Should be built after IGC but before the final Compute Runtime assembly.

### Versioning Rationale
- **Compatibility Baseline**: Version 2.2.0 is used as the verified baseline for this specific `intel-compute-runtime` release.
- **Upgrade Flexibility**: `libva` handles video acceleration interfaces. Since 2.2.0 is relatively old, it may not perfectly display hardware info for the latest GPU architectures. If hardware reporting is incomplete, it is safe to upgrade to a newer 2.x version, as it typically maintains API compatibility for OpenCL.
