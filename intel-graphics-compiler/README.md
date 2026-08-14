# intel-graphics-compiler (IGC)

Maintainer reference and developer guide for building and updating the `intel-graphics-compiler` plan in Wright.

---

## 1. Overview & Architectural Design

`intel-graphics-compiler` (IGC) provides the OpenCL and Level Zero compilation engine for Intel GPU platforms.

### In-Tree Submodule Requirement
IGC modifies and patches internal LLVM CodeGen and SPIR-V passes. It requires a closely matched set of submodules:
- `llvm-project`
- `opencl-clang`
- `SPIRV-LLVM-Translator`
- `SPIRV-Tools`
- `SPIRV-Headers`
- `vc-intrinsics`

> **Note**: Do not attempt to dynamically link against system-wide LLVM or standalone `opencl-clang` packages. In-tree compilation under `${WORKDIR}` is mandatory to prevent ABI/API mismatches and runtime driver crashes.

---

## 2. Locating Upstream Pinned Component Versions

When bumping or updating the `intel-graphics-compiler` plan version, submodules must be aligned with upstream pinned commits/tags.

### Primary Source: Intel Upstream Repository (First-Hand Authority)
Always inspect official upstream manifests in the [intel/intel-graphics-compiler](https://github.com/intel/intel-graphics-compiler) repository for the targeted release tag (e.g. `v2.38.2`):

1. **Git Submodules**: Check `.gitmodules` at the root of the repository for exact submodule commit SHAs for `opencl-clang`, `SPIRV-LLVM-Translator`, `SPIRV-Tools`, `SPIRV-Headers`, and `vc-intrinsics`.
2. **LLVM Baseline**: Check `IGC/CMakeLists.txt` or `external/llvm/llvm_deps.cmake` for the default `IGC_OPTION__LLVM_PREFERRED_VERSION` (e.g. `17.0.6`).
3. **Release Notes & Tags**: Check [Upstream GitHub Releases](https://github.com/intel/intel-graphics-compiler/releases) for release-specific component notes.

### Secondary Reference: Downstream Distribution Packages
To verify production-tested commit combinations, cross-reference with distribution packaging manifests:
- **Arch Linux Packaging**: [Arch Linux IGC PKGBUILD](https://gitlab.archlinux.org/archlinux/packaging/packages/intel-graphics-compiler/-/blob/main/PKGBUILD) (Inspect variables: `_llvmver`, `_vciver`, `_spirv_tools_commit`, `_spirv_headers_commit`, `_spirv_llvm_commit`, `_opencl_clang_commit`).

---

## 3. Known Build Issues & Troubleshooting

### Issue 1: Missing `<cstdint>` under GCC 15+ (Header Cleanups)
- **Symptom**: Compilation fails during the `compile` stage with errors such as `'uint64_t' has not been declared` or `expected identifier before ':' token` in LLVM headers.
- **Root Cause**: GCC 15 and newer clean up standard C++ library headers and no longer transitively include `<cstdint>` via headers like `<string>` or `<vector>`.
- **Resolution**:
  - In `pipeline.prepare`, prepend `#include <cstdint>` to `llvm-project/llvm/lib/Target/X86/MCTargetDesc/X86MCTargetDesc.h`:
    ```bash
    sed -i '1i #include <cstdint>' ${WORKDIR}/llvm-project/llvm/lib/Target/X86/MCTargetDesc/X86MCTargetDesc.h
    ```
  - In `pipeline.configure`, export `-include cstdint` in `CXXFLAGS`:
    ```bash
    export CXXFLAGS="${CXXFLAGS} -include cstdint"
    ```

### Issue 2: CMake Missing Submodule or LLVM Source Directories
- **Symptom**: Configuration fails with errors like `Cannot find LLVM sources, please provide sources path by IGC_OPTION__LLVM_SOURCES_DIR` or `add_subdirectory given source ... SPIRV-Tools which is not an existing directory`.
- **Root Cause**: Extracted archive directories differ from the relative paths expected by IGC CMake scripts (e.g., `${WORKDIR}/source/SPIRV-Tools`).
- **Resolution**:
  - In `pipeline.prepare`, normalize extracted top-level directories and wire symlinks under `${WORKDIR}/source/`:
    ```bash
    mkdir -p ${WORKDIR}/source
    ln -sf ${WORKDIR}/vc-intrinsics ${WORKDIR}/source/vc-intrinsics
    ln -sf ${WORKDIR}/SPIRV-Tools ${WORKDIR}/source/SPIRV-Tools
    ln -sf ${WORKDIR}/SPIRV-Headers ${WORKDIR}/source/SPIRV-Headers
    ln -sf ${WORKDIR}/SPIRV-LLVM-Translator-IGC-LLVM ${WORKDIR}/source/SPIRV-LLVM-Translator-IGC-LLVM
    ln -sf ${WORKDIR}/opencl-clang ${WORKDIR}/source/opencl-clang
    ln -sf ${WORKDIR}/llvm-project ${WORKDIR}/source/llvm-project
    ```
  - In `pipeline.configure`, specify the LLVM source directory:
    ```cmake
    -DIGC_OPTION__LLVM_SOURCES_DIR="${WORKDIR}/llvm-project"
    ```
