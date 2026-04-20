# intel-compute-runtime

## Version: 26.09.37435.1

This is the **top-level runtime** of the Intel GPU software stack.

### Build Hierarchy (Build Order)
This component must be built last in the following sequence:
1. **Layer 0 (Compiler Core)**: `llvm16` -> `intel-graphics-compiler (igc)`
2. **Layer 1 (Hardware Abstraction)**: `intel-gmmlib`, `metee` -> `igsc`
3. **Layer 2 (Interfaces)**: `libva`, `level-zero`
4. **Layer 3 (Runtime)**: `intel-compute-runtime` (Current)

### Versioning Rationale
- **Official Reference**: This version is selected based on recommendations from the [Intel Compute Runtime Releases](https://github.com/intel/compute-runtime/releases).
- **Critical Dependency**: There is a strong coupling between this runtime, `igc`, and `llvm16`. Any change in the compiler layer necessitates a full rebuild of this runtime.
- **Note on libva**: While version 2.2.0 is the recommended baseline for compatibility, it is an older version. For newer GPU generations, you may upgrade to a more recent 2.x version of `libva` to improve hardware information reporting and codec support without breaking the OpenCL stack.
