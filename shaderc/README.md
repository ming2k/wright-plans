# shaderc

> Part of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
Google's shader compilation wrapper — provides `glslc`, a GLSL/HLSL → SPIR-V
compiler built on glslang + spirv-tools.

## What it does
Compiles shaders to SPIR-V. **llama.cpp uses `glslc` at build time** to generate
all its Vulkan compute shaders (the `-O` path runs spirv-opt).

## Why it's in Theseus
The build-time shader compiler for llama.cpp's Vulkan backend (`provides = glslc`).

## Version & constraints
- **Current version**: `2026.2` (date train).
- **Must match (the critical constraint)**: shaderc hard-pins exact **spirv-tools**,
  **glslang**, and **spirv-headers** revisions in its upstream `DEPS`. The plan
  de-vendors these (`sed '/third_party/d'`) and links the system copies, so the
  installed versions **must correspond to shaderc's pins**. Verify before bumping:
  ```sh
  curl -s "https://raw.githubusercontent.com/google/shaderc/v2026.2/DEPS" \
    | grep -E 'spirv_tools_revision|glslang_revision|spirv_headers_revision'
  ```
  Resolve each commit → version via the repo's `CHANGES`. A mismatch is the exact
  bug that caused untested spirv-opt behavior (shaderc 2026.1 + spirv-tools 2026.2).
- **Verify**: `glslc --version` prints shaderc / spirv-tools / glslang stamps.
- **Rebuild after a bump**: llama.cpp (and any Vulkan app that compiles shaders).
