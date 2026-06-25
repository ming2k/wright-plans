# spirv-cross

> Part of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
Library/tool for parsing SPIR-V and converting it back to high-level shader
languages (GLSL/MSL/HLSL) — i.e. reflection and cross-compilation.

## What it does
Reflects and translates SPIR-V. Built shared (`SPIRV_CROSS_SHARED=ON`, CLI off)
so it ships `libspirv-cross-*.so` for consumers that do shader translation.

## Why it's in Theseus
Part of the Vulkan SDK; used by GPU tooling and translation layers that ingest
SPIR-V. Independent of the glslc/llama.cpp build path.

## Version & constraints
- **Current version**: `1.4.350.1` — **Vulkan-SDK lockstep** train (tag `vulkan-sdk-1.4.350.1`).
- **Must match**: bump together with the rest of the Vulkan-SDK set
  (spirv-headers, vulkan-headers, vulkan-loader, vulkan-tools) to the same tag.
- **Rebuild after a bump**: consumers that link libspirv-cross.
