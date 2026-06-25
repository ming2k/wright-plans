# vulkan-headers

> Part of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
Vulkan API header files and the XML API registry. Header-only; `arch = "any"`.

## What it does
Defines the Vulkan API surface that the loader, ICDs (mesa ANV), and applications
compile against. Installs to `/usr`.

## Why it's in Theseus
Build dependency of **vulkan-loader**, **vulkan-tools**, **mesa**, and any app
targeting Vulkan. The header version (`1.4.350`) is the Vulkan API level.

## Version & constraints
- **Current version**: `1.4.350.1` — **Vulkan-SDK lockstep** train (tag `vulkan-sdk-1.4.350.1`).
- **Must match**:
  - bump together with the Vulkan-SDK set (spirv-headers, spirv-cross,
    vulkan-loader, vulkan-tools) to the same tag.
  - **vulkan-loader version must equal this** (constraint #3).
- **Rebuild after a bump**: vulkan-loader → vulkan-tools; mesa.
