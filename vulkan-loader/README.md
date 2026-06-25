# vulkan-loader

> Part of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
The Vulkan loader (`libvulkan.so`) — the runtime that dispatches Vulkan calls to
installed ICDs. Built **Wayland-only** (X11 WSI disabled).

## What it does
Discovers and loads the GPU driver (mesa ANV ICD) at runtime and routes every
`vk*` call to it. Every Vulkan application links against it.

## Why it's in Theseus
Runtime dependency of **llama.cpp** (Vulkan backend), **vulkan-tools**, and the
whole Wayland/Vulkan desktop. Without it no Vulkan app can find the driver.

## Version & constraints
- **Current version**: `1.4.350.1` — **Vulkan-SDK lockstep** train (tag `vulkan-sdk-1.4.350.1`).
- **Must match**: built against **vulkan-headers**; keep its version **equal** to
  vulkan-headers (constraint #3). Bump with the rest of the Vulkan-SDK set.
- **WSI constraint**: Wayland-only build — do not enable X11 WSI without aligning mesa.
- **Rebuild / verify after a bump**: vulkan-tools; `vulkaninfo --summary` must load the ICD.
