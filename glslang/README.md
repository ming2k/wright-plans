# glslang

> Part of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
The Khronos reference GLSL/ESSL front-end and SPIR-V generator.

## What it does
Compiles GLSL/ESSL to SPIR-V. Built with `-DALLOW_EXTERNAL_SPIRV_TOOLS=ON` and
`-DBUILD_SHARED_LIBS=ON` so it uses the system spirv-tools and ships
`libglslang.so` / `libSPIRV.so`.

## Why it's in Theseus
The GLSL front-end inside **shaderc** (glslc) and a build dependency of **mesa**.

## Version & constraints
- **Current version**: `16.3.0` (semver, independent train).
- **Must match**:
  - Built against the system **spirv-tools** / **spirv-headers** — keep them compatible.
  - **shaderc** hard-pins a glslang revision in its `DEPS`; the installed glslang
    must match that pin (constraint #1).
- **Note**: glslang ships **no pkg-config `.pc`** — shaderc's version stamp shows
  `unknown` for glslang; cosmetic only.
- **Rebuild after a bump**: shaderc → llama.cpp; mesa.
