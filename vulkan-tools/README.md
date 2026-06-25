# vulkan-tools

> Part of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
Vulkan utility programs — notably **`vulkaninfo`** (and cube, disabled here).

## What it does
Reports driver/device/extension info. `vulkaninfo --summary` is the first-line
diagnostic for "is the Vulkan stack healthy and which ICD is loaded".

## Why it's in Theseus
Diagnostics for the GPU stack (used throughout the llama.cpp `ErrorDeviceLost`
investigation to confirm Mesa 26.1.3 ANV on the ARL iGPU).

## Version & constraints
- **Current version**: `1.4.350.1` — **Vulkan-SDK lockstep** train (tag `vulkan-sdk-1.4.350.1`).
- **Must match**: built against **vulkan-headers**, links **vulkan-loader**; bump
  with the rest of the Vulkan-SDK set to the same tag.
- **Verify after a bump**: `vulkaninfo --summary` lists the expected device + driver version.
