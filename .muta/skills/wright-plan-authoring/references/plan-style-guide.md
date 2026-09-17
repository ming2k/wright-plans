# Wright Plan Authoring Style Guide & Standard Conventions

This guide establishes the standard manifest writing conventions, styling rules, and architectural best practices for authoring `plan.toml` files, derived directly from the `wright` engine architecture and official documentation (`/home/ming/projects/wright/docs/`).

---

## 1. Core Design Philosophy (The Wright Way)

1. **No Magic Behavior (ADR-0004)**: Everything in a plan is declarative and explicit. Patches are not auto-applied, directories are not auto-guessed, and files are not auto-split. What you write in `plan.toml` is what executes.
2. **Single-Source Staging, Multi-Target Slicing**: Pipeline scripts install everything into a single `${STAGING_DIR}` (`/output` in isolation). Wright's slicing engine then dispatches files into individual parts (`.wright.tar.zst`) per `[[output]]` and `[[discard]]` rules.
3. **UsrMerge & FHS Compliance (ADR-0007)**: Theseus Linux is a pure UsrMerge system (`/bin`, `/sbin`, `/lib`, `/lib64` are symlinks to `/usr/bin`, `/usr/lib`).
   - Binaries **must** be staged under `/usr/bin` (or `/usr/libexec` for internal helpers). Never stage into `/sbin` or `/bin`.
   - Libraries **must** be staged under `/usr/lib`. Never use `/lib64` or architecture-specific subdirectories (unless upstream requires it, e.g. OpenVINO runtime).
   - User configs belong in `/etc/`.
   - Do not bypass FHS checks unless packaging third-party self-contained bundles (`skip_fhs_check = true` in `/opt/...`).
4. **Desktop Target & Upstream Fidelity**:
   - Prefer native Wayland over X11/XWayland.
   - Prefer upstream configure flags over downstream source patches. Keep patches minimal, numbered, and documented.

---

## 2. Manifest Layout & Formatting Standards

Maintain a clean, predictable TOML structure ordered as follows:

```toml
# 1. Top-Level Metadata
name = "example"
version = "1.2.3"
release = 1
description = "Clear, concise summary of the software"
license = "MIT"
arch = "x86_64"
url = "https://example.com/project"
maintainer = "Maintainer Name <email@example.com>"

# 2. Plan-Level Dependencies (Build & Link)
build_deps = ["cmake", "ninja", "pkg-config"]
link_deps = ["openssl", "zlib >= 1.2.0"]

# 3. Sources
[[sources]]
type = "http"
url = "https://example.com/releases/example-${VERSION}.tar.gz"
sha256 = "..."
extract_to = "source"

[[sources]]
type = "local"
path = "patches/0001-fix-build.patch"

# 4. Build Options (Optional)
[options]
ccache = true
env = { CFLAGS = "-O2 -pipe", CXXFLAGS = "-O2 -pipe" }

# 5. Pipeline Stages (in default execution order)
[pipeline.prepare]
script = '''
cd source/example-${VERSION}
patch -Np1 < ${WORKDIR}/0001-fix-build.patch
'''

[pipeline.configure]
script = '''
cd source/example-${VERSION}
cmake -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr
'''

[pipeline.compile]
script = '''
cd source/example-${VERSION}
ninja -C build -j$(nproc)
'''

[pipeline.check]
script = '''
cd source/example-${VERSION}
ninja -C build test
'''

[pipeline.staging]
script = '''
cd source/example-${VERSION}
DESTDIR=${STAGING_DIR} ninja -C build install
'''

# 6. Outputs & Slicing
[[output]]
name = "example"
runtime_deps = ["openssl", "zlib"]

[[output]]
name = "example-dev"
description = "Development headers and pkg-config files"
include = ["/usr/include/**", "/usr/lib/pkgconfig/**"]

# 7. Discards (if any)
[[discard]]
include = ["/usr/share/info/**"]
reason = "Info manuals are not packaged"
```

---

## 3. Detailed Styling & Writing Rules

### A. Source Declarations (`[[sources]]`)
- **Source Type Priority**:
  1. `type = "http"` (release tarball / host archive) — Preferred. Fast, cached, checksum-verified.
  2. `type = "git"` with `ref = "v${VERSION}"` (shallow clone, cached snapshot).
  3. `type = "git"` with 40-char commit hash.
- **`extract_to = "source"` Rule**:
  - Always use `extract_to = "source"` on the primary archive source to prevent flat tarballs from polluting `${WORKDIR}`.
  - Never use `extract_to` on local patches or single config files (they land directly in `${WORKDIR}`).
- **Local Patches**:
  - Store patches in a `patches/` folder: `patches/0001-description.patch`.
  - Reference using `type = "local"`, `path = "patches/0001-description.patch"`.
  - In `pipeline.prepare`, reference with `${WORKDIR}/0001-description.patch` (Wright strips path prefixes in `${WORKDIR}`).

### B. Dependency Declarations
- **Position Locking**:
  - `build_deps` & `link_deps`: Top-level ONLY.
  - `runtime_deps`: `[[output]]` table ONLY.
- **Reference Syntax**:
  - Single-output plan: `"plan-name"` (e.g. `"openssl"`, `"glibc"`).
  - Specific output of a multi-output plan: `"plan-name:output-name"` (e.g. `"llvm:clang"`, `"gcc:gcc-libs"`).
  - Version constraint: `"pkg >= 1.2.3"`, `"pkg = 2.0"`.
- **System vs. In-Tree Dependencies**:
  - If upstream bundles a 3rdparty library and compiles it statically in-tree, do **not** add it to `build_deps`/`link_deps`.
  - Only declare what the build host must provide (`build_deps`) and what the final binaries dynamically link against on Theseus Linux (`link_deps`).

### C. Pipeline Scripting Conventions
- **Defensive Scripting**: Wright executes scripts with `bash -e -o pipefail`. Any non-zero command fails the stage immediately.
- **Explicit Directory Navigation**: Always start stage scripts with `cd source/<unpacked-dir-name>`.
- **Atomic Installation**: When installing files manually in `staging`:
  - Use `install -Dm755 src/bin "${STAGING_DIR}/usr/bin/bin"`
  - Use `install -Dm644 src/file "${STAGING_DIR}/usr/share/pkg/file"`
  - Avoid bare `cp` + `chmod` chains where possible.
- **Environment Variables**: Prefer setting variables in `[options] env` or stage-level `env = { ... }` rather than inline `export` in shell scripts for better cache traceability.

### D. Isolation Level Selection
- **`strict` (Default)**:
  - C, C++, CMake, Meson, autotools, and any build that does not need network access.
  - Network and IPC are isolated; overlayfs protects host root.
- **`relaxed`**:
  - Rust (`cargo build`), Go (`go build`), Node.js (`npm`), Python (`pip`) when dependencies are fetched at build time.
  - Also used when IPC with the host is required.
- **`none`**:
  - Strictly discouraged; only used if container namespace creation is unsupported or requires direct host hardware access.

### E. Output Slicing & Discard Discipline
- **Mutual Exclusivity**:
  - Every non-catch-all output must have specific `include` and `exclude` patterns so no single file is matched by two outputs.
  - If `example-dev` claims `/usr/include/**` and `/usr/lib/pkgconfig/**`, the main `example` output can act as the catch-all (no `include`) or specify `exclude = ["/usr/include/**", "/usr/lib/pkgconfig/**"]`.
- **Discards (`[[discard]]`)**:
  - Always provide a meaningful `reason`.
  - Use discards for static libraries (`/usr/lib/*.a`), libtool archives (`/usr/lib/*.la`), charset aliases, or unwanted manual formats.

### F. Versioning Rules
- `version`: Match upstream tag or release string verbatim.
- `release`: Increments (`1`, `2`, `3`...) when patches or build flags are adjusted in the plan. **Must reset to `1` when `version` is updated**.
- `epoch`: Defaults to 0; increment only if upstream renames or changes scheme (e.g. `2024.1` → `1.0.0`) so the package manager recognizes it as newer.

### G. Handling Circular Dependencies (`mvp.toml`)
- When two plans cyclically depend on each other at build time (e.g. `freetype` ↔ `harfbuzz`, `cairo` ↔ `pango`), create `mvp.toml` next to `plan.toml`.
- In `mvp.toml`, strip the cyclic dependency from `link_deps`/`build_deps` and configure with feature flags disabled (e.g. `--without-harfbuzz`).
- Do not duplicate metadata or sources in `mvp.toml`.
