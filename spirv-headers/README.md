# spirv-headers

> Root of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
Machine-readable parts of the SPIR-V specification (headers, grammar JSON).
Header-only; `arch = "any"`.

## What it does
Provides the canonical SPIR-V enums/grammar that every SPIR-V producer and
consumer compiles against. Installs to `/usr`.

## Why it's in Theseus
The base dependency for the entire shader stack: spirv-tools, glslang, shaderc,
spirv-cross, spirv-llvm-translator, vulkan-headers and mesa all build against it.
A mismatch here ripples through every Vulkan/OpenCL component.

## Version & constraints
- **Current version**: `1.4.350.1` — **Vulkan-SDK lockstep** train (tag `vulkan-sdk-1.4.350.1`).
- **Must match**: bump together with spirv-cross, vulkan-headers, vulkan-loader,
  vulkan-tools to the **same** `vulkan-sdk-*` tag. spirv-tools and shaderc pin a
  specific spirv-headers revision — see constraints #1/#5 in the shared doc.
- **Rebuild after a bump**: spirv-tools → glslang → shaderc → llama.cpp;
  spirv-llvm-translator; vulkan-headers → vulkan-loader → vulkan-tools; mesa.
