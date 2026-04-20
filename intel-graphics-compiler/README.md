# intel-graphics-compiler (IGC)

## Version: v2.30.1

### Build Hierarchy (Layer 0)
1. **Prerequisites**: System-provided `llvm16` libraries.
2. **Current Component**: `intel-graphics-compiler`
3. **Downstream Dependency**: `intel-compute-runtime`

### Versioning Rationale
- **LLVM Binding**: IGC is deeply integrated with specific LLVM internal APIs (pinned to `llvm16` here). It serves as the core engine for OpenCL kernel compilation.
- **Runtime Alignment**: This version must strictly match the requirements of `intel-compute-runtime`. Any modification to IGC requires a mandatory rebuild of the top-level runtime.
