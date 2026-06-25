# SPIR-V / Vulkan Shader Toolchain — Coupling & Update Policy

Shared reference for the SPIR-V, shader-compiler, and Vulkan plans. Each plan in
this cluster carries its own `README.md` (what / does / why); this file holds the
cross-cutting **dependency graph**, **version trains**, and **bump policy** so a
single careless update cannot break the GPU stack.

## Dependency graph

```
spirv-headers ─┬─> spirv-tools ─┬─> glslang ─┐
               │                │            ├─> shaderc ─> llama.cpp (build: glslc compiles Vulkan shaders)
               │                └────────────┘
               ├─> spirv-cross
               ├─> spirv-llvm-translator (+ llvm) ─> intel-compute-runtime
               └─> vulkan-headers ─> vulkan-loader ─┬─> vulkan-tools
                                                    └─> (runtime) every Vulkan app: llama.cpp, mesa ICD
mesa ── build_deps ──> spirv-headers, glslang ;  runtime ──> vulkan-loader
```

Rebuild flows **left → right**: bumping a node requires rebuilding everything
reachable to its right.

## Version trains

| Train | Plans | Rule |
|-------|-------|------|
| **Vulkan-SDK lockstep** (`vulkan-sdk-X.Y.Z.W`) | spirv-headers, spirv-cross, vulkan-headers, vulkan-loader, vulkan-tools | All five move **together** to the same SDK tag. Never mix SDK versions. Current: `1.4.350.1`. |
| **spirv-tools** (date `YYYY.N`) | spirv-tools | Pins a SPIR-V-Headers revision via upstream `DEPS`; align to the same SDK cycle as `spirv-headers`. Current: `2026.2`. |
| **glslang** (semver) | glslang | Built against the system spirv-tools/headers. Current: `16.3.0`. |
| **shaderc** (date `YYYY.N`) | shaderc | **Hard-pins** exact `spirv-tools` + `glslang` + `spirv-headers` revisions in its `DEPS`. The installed versions must match those pins. Current: `2026.2`. |
| **spirv-llvm-translator** (LLVM major) | spirv-llvm-translator | Major version **must equal** the installed `llvm` major. Current: `22.1.2` ↔ llvm 22.x. |

## Hard constraints (break these → broken GPU stack)

1. **shaderc ⇄ spirv-tools / glslang / spirv-headers** — the installed versions
   must correspond to the commits pinned in shaderc's `DEPS`. This is what bit us
   (shaderc 2026.1 was built against drifted spirv-tools 2026.2 / glslang 16.3.0).
2. **Vulkan-SDK set shares one tag** — spirv-headers, spirv-cross, vulkan-headers,
   vulkan-loader, vulkan-tools all on the same `vulkan-sdk-*` tag.
3. **vulkan-loader version == vulkan-headers version** — the loader is built
   against the headers; keep them equal.
4. **spirv-llvm-translator major == llvm major** — translator 22.x needs llvm 22.x.
5. **spirv-tools ⇄ spirv-headers** — spirv-tools pins a SPIRV-Headers revision;
   use the spirv-headers from the matching SDK cycle.

## Update checklist

Before bumping any plan in this cluster:

1. **Identify the train** (table above). For the Vulkan-SDK set, bump all five to
   the same new `vulkan-sdk-*` tag in one change.
2. **For shaderc**, resolve its pins and confirm they match what is installed:
   ```sh
   ver=2026.2   # target shaderc version
   curl -s "https://raw.githubusercontent.com/google/shaderc/v${ver}/DEPS" \
     | grep -E 'spirv_tools_revision|glslang_revision|spirv_headers_revision'
   # resolve each commit -> version via that repo's CHANGES/CHANGES.md
   ```
   If shaderc pins newer spirv-tools/glslang than installed, bump those first.
3. **For spirv-llvm-translator**, confirm `llvm` major matches the translator major.
4. **Bump `release`** (not `version`) on the plan when only build flags/patches/
   deps change; reset `release = 1` on every `version` bump (see
   `wright-docs/how-to/write-a-plan.md`).
5. **Rebuild downstream in graph order** and verify:
   ```sh
   glslc --version          # shaderc / spirv-tools / glslang stamps
   vulkaninfo --summary     # loader + ICD load cleanly
   ```

## Consumers (downstream — where breakage surfaces)

| Consumer | Uses | Constraint |
|----------|------|------------|
| llama.cpp | `shaderc` (build: glslc → Vulkan SPIR-V), `spirv-headers`, `vulkan-loader` (runtime) | Rebuild after any shaderc/spirv-tools/glslang bump; shader miscompiles show here. |
| mesa (ANV) | `spirv-headers`, `glslang` (build), `vulkan-loader` (runtime ICD) | Rebuild after spirv-headers/glslang bump. |
| intel-compute-runtime | `spirv-llvm-translator` (OpenCL/L0 SPIR-V) | Rebuild after translator/llvm bump. |
