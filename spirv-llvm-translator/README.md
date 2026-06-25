# spirv-llvm-translator

> Part of the SPIR-V / Vulkan toolchain. See
> [`../TOOLCHAIN-spirv-vulkan.md`](../TOOLCHAIN-spirv-vulkan.md) for the full
> dependency graph and bump policy.

## What it is
Bi-directional translator between SPIR-V and LLVM IR.

## What it does
Converts LLVM IR ↔ SPIR-V. Built shared and linked against `llvm:llvm-libs`;
consumed by the OpenCL/Level-Zero compilation path.

## Why it's in Theseus
Needed by **intel-compute-runtime** (OpenCL / oneAPI Level Zero) to emit SPIR-V
from the LLVM-based compiler.

## Version & constraints
- **Current version**: `22.1.2` — **tracks the LLVM major** (independent of the Vulkan SDK).
- **Must match (hard constraint)**: the translator **major must equal the installed
  `llvm` major** (22.x ↔ llvm 22.x). It also builds against **spirv-headers**
  (`LLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR=/usr`).
- **Bump trigger**: bump this whenever `llvm` is bumped to a new major.
- **Rebuild after a bump**: intel-compute-runtime.
