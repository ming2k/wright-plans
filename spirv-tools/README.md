# spirv-tools

> Part of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
API and command-line tools for processing SPIR-V modules — assembler,
disassembler, validator, and **spirv-opt** (the optimizer).

## What it does
Optimizes and validates SPIR-V. `spirv-opt` is invoked (via `glslc -O`) when
llama.cpp generates its Vulkan compute shaders, so regressions here can produce
slow or miscompiled shaders.

## Why it's in Theseus
Required by glslang and shaderc; the optimizer behind every `-O` shader build.

## Version & constraints
- **Current version**: `2026.2` (date train `YYYY.N`).
- **Must match**:
  - Built with `-DSPIRV-Headers_SOURCE_DIR=/usr` → uses the system **spirv-headers**;
    keep within the same SDK cycle (constraint #5).
  - **shaderc** hard-pins a spirv-tools revision in its `DEPS`; the installed
    version must equal that pin (constraint #1). This was the source of the
    earlier drift (shaderc 2026.1 vs spirv-tools 2026.2).
- **Rebuild after a bump**: glslang, shaderc, then llama.cpp.
