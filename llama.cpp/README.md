# llama.cpp Plan for Wright Linux

## 1. Overview

This plan builds **llama.cpp** (release `b9789`) with multi-backend hardware acceleration for Intel CPUs, Intel GPUs, Intel NPUs, and Vulkan devices.

It installs the complete suite of CLI tools and OpenAI-compatible server binaries into `/usr/lib/llama.cpp` with user-accessible symlinks in `/usr/bin/`.

---

## 2. Hardware Acceleration Backends

| Backend | Flag | Supported Hardware | Environment Variable |
| :--- | :--- | :--- | :--- |
| **OpenVINO CPU** | `-DGGML_OPENVINO=ON` | Intel AVX2 / AVX-512 / AMX | `GGML_OPENVINO_DEVICE=CPU` |
| **OpenVINO GPU** | `-DGGML_OPENVINO=ON` | Intel Arc dGPU, Iris Xe, UHD Graphics | `GGML_OPENVINO_DEVICE=GPU` |
| **OpenVINO NPU** | `-DGGML_OPENVINO=ON` | Intel Core Ultra NPU (Meteor Lake / Arrow Lake / Lunar Lake) | `GGML_OPENVINO_DEVICE=NPU` |
| **Vulkan** | `-DGGML_VULKAN=ON` | Discrete & Integrated Vulkan GPUs | Automatically enumerated |
| **Native CPU** | Default | x86-64 OpenMP SIMD GEMM | `LLAMA_ARG_THREADS` |

---

## 3. Key Architectural Decisions & Patches

### A. OpenVINO Integration via Standard FHS
* Configured to consume the system OpenVINO runtime from `/usr/lib` and `/usr/include` using CMake's standard `find_package(OpenVINO REQUIRED COMPONENTS Runtime ONNX)`.
* Links against `openvino::runtime` and `openvino::frontend::onnx` without requiring custom `LD_LIBRARY_PATH` exports.

### B. Intel NPU Compatibility Patches
Upstream `llama.cpp` OpenVINO backend includes hints that may cause crashes on certain NPU firmware and compiler revisions:
1. `0001-openvino-do-not-set-execution-mode-hint-on-npu.patch`:
   * Disables unsupported execution mode hints on NPU devices.
2. `0002-openvino-avoid-unsupported-npu-dynamic-quantization-option.patch`:
   * Disables unsupported dynamic quantization options on NPU devices.

### C. Web Server & Secure Endpoints (`-DLLAMA_OPENSSL=ON`)
* Builds `llama-server` with native HTTPS/TLS support via system OpenSSL.

### D. Global CLI Tool Symlinks
All major binaries are staged in `/usr/lib/llama.cpp/bin/` and symlinked to `/usr/bin/`:
* `llama-cli`: Interactive and prompt-based text generation CLI.
* `llama-server`: High-performance OpenAI-compatible HTTP/WebSocket API server with built-in web UI.
* `llama-bench`: Micro-benchmarking utility for prompt processing and token generation speeds.
* `llama-quantize`: GGUF model quantizer (e.g. Q4_K_M, Q8_0, IQ4_XS).
* `llama-perplexity`: Perplexity evaluation on text corpora.
* `llama-embedding`: Text embedding generation tool.

---

## 4. Usage & Verification

### A. List Detected Hardware Devices
```bash
llama-cli --list-devices
```
Output:
```text
Available devices:
  Vulkan0: Intel(R) Graphics (ARL) (23686 MiB, 21317 MiB free)
  OPENVINO0: OpenVINO Runtime (31581 MiB, 31581 MiB free)
```

### B. Run Inference on OpenVINO
```bash
# Target Intel NPU
GGML_OPENVINO_DEVICE=NPU llama-cli -m model.gguf -p "Explain quantum mechanics" -n 128

# Target Intel GPU
GGML_OPENVINO_DEVICE=GPU llama-cli -m model.gguf -p "Explain quantum mechanics" -ngl 99

# Target Intel CPU with OpenVINO acceleration
GGML_OPENVINO_DEVICE=CPU llama-cli -m model.gguf -p "Explain quantum mechanics"
```

### C. Launch OpenAI-Compatible API Server
```bash
llama-server -m model.gguf --host 0.0.0.0 --port 8080 -ngl 99
```
