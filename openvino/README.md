# Intel OpenVINO Toolkit Plan for Wright Linux

## 1. Overview & Architecture

This plan builds and packages the **Intel OpenVINO Toolkit (v2026.2.0)** from source into the standard Linux Filesystem Hierarchy Standard (FHS) tree (`/usr`).

OpenVINO serves as the core system runtime for deep learning inference acceleration across Intel hardware, powering downstream AI engines such as `llama.cpp` (`-DGGML_OPENVINO=ON`), OpenCV, ONNX Runtime, and native C/C++ inference applications.

---

## 2. Key Architectural Decisions & Engineering Know-How

### A. Declarative Git Submodules (`submodules = true`)
* **Problem**: OpenVINO depends on multiple git submodules (`oneDNN`, `xbyak`, `ittapi`, `mlas`, `level-zero-ext`, `nlohmann_json`, `protobuf`, etc.). Downloading submodules inside build scripts breaks Wright's strict sandbox network isolation.
* **Solution**: Declarative `submodules = true` in `[[sources]]`. Wright clones and recursively fetches all submodules during the **Charge / Fetch stage**, archiving the complete source tree into an immutable `.tar.zst` snapshot in `/var/cache/wright/sources/`. All subsequent configure, compile, and staging steps run 100% offline.

### B. Standard FHS Packaging vs. Upstream Archive Layout
* **Problem**: OpenVINO's upstream CMake defaults to `CPACK_GENERATOR=TGZ`, designed for standalone tarballs extracting into `/opt/intel/openvino/runtime/...`. This hardcodes `runtime/lib/intel64` and `runtime/3rdparty/tbb` into exported `OpenVINOTargets.cmake` and `OpenVINOConfig.cmake`, causing downstream `find_package(OpenVINO)` to fail when installed to `/usr`.
* **Solution**:
  1. Configured `-DCPACK_GENERATOR=BREW` to activate OpenVINO's UNIX distribution packaging rules (`cmake/developer_package/packaging/common-libraries.cmake`).
  2. In `pipeline.prepare`, patched `install_tbb.cmake` to remove the Debian/Fedora-specific guard requiring distro `libtbb-dev`:
     ```bash
     sed -i 's/NOT ENABLE_SYSTEM_TBB/FALSE/g' source/src/cmake/install_tbb.cmake
     ```
  3. Relocated TBB metadata and resource installation to `/usr/share/openvino/tbb`:
     ```bash
     sed -i 's|runtime/3rdparty/tbb|share/openvino/tbb|g' source/src/cmake/install_tbb.cmake
     ```
  4. In `pipeline.staging`, explicitly installed TBB runtime libraries (`libtbb.so*`, `libtbbmalloc.so*`, `libtbbbind_2_5.so*`) into `/usr/lib/` and TBB CMake modules into `/usr/share/openvino/tbb/`, ensuring downstream `find_package(OpenVINO)` and `set_and_check(_tbb_dir)` resolve cleanly.

### C. Build & ABI Isolation Choices
* **OpenCL C++ Wrapper (`-DENABLE_SYSTEM_OPENCL=OFF`)**:
  * Upstream `ocl_wrapper.hpp` relies on OpenCL 1.1 legacy macros (`CL_HPP_PARAM_NAME_INFO_1_1_DEPRECATED_IN_2_0_`), which were removed in newer system `opencl-clhpp` headers.
  * Setting `-DENABLE_SYSTEM_OPENCL=OFF` compiles with OpenVINO's verified in-tree OpenCL wrapper headers, while **still dynamically binding to `/usr/lib/libOpenCL.so.1` (`intel-compute-runtime`) at runtime**.
* **Protobuf Isolation (`-DENABLE_SYSTEM_PROTOBUF=OFF`)**:
  * Avoids Protobuf 7.x / Abseil ABI breakage with CMake's legacy `FindProtobuf.cmake`.
* **Node.js / JS Bindings (`-DENABLE_JS=OFF`)**:
  * Strips out Node.js bindings to prevent CMake `FetchContent` from attempting online downloads of `node-api-headers`.

---

## 3. Hardware Acceleration Matrix

| Hardware Engine | Backend Technology | Required Runtime Drivers |
| :--- | :--- | :--- |
| **Intel CPU** | AVX2 / AVX-512 / AMX / oneDNN + TBB | `glibc`, `gcc:libstdc++` |
| **Intel GPU** | Intel Arc dGPU, Iris Xe, UHD Graphics | `intel-compute-runtime`, `ocl-icd` |
| **Intel NPU** | Intel Core Ultra (Meteor Lake / Arrow Lake / Lunar Lake) | `level-zero`, `intel-npu-driver` |
| **Virtual Dispatch** | `AUTO`, `MULTI`, `HETERO` | Native in OpenVINO runtime |

---

## 4. Diagnostics & Verification

The plan builds and installs `/usr/bin/openvino-query-device`. Run it to inspect all active hardware backends detected on the host system:

```bash
$ openvino-query-device
CPU
GPU
NPU
```

---

## 5. Downstream Consumer Integration (e.g. `llama.cpp`)

Any CMake consumer can locate and link against OpenVINO using standard CMake syntax:

```cmake
find_package(OpenVINO REQUIRED COMPONENTS Runtime ONNX)
target_link_libraries(my_app PRIVATE openvino::runtime openvino::frontend::onnx)
```
