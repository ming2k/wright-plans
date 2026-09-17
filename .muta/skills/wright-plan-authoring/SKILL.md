---
name: wright-plan-authoring
description: "Author, write, and package new wright plan.toml manifests and folios for the wright from-source package manager in Theseus Linux. Use whenever the user asks to write a new wright plan, author a plan.toml or folio.toml, package software from source for wright, create build lifecycle stages (configure, compile, staging), specify build_deps/link_deps/runtime_deps, define output slicing and discards, write patches, configure isolation levels, or apply wright style conventions. Also covers authoring circular dependency workarounds (mvp.toml)."
short-description: "Author and write wright plan.toml and folio.toml manifests"
version: "1.0.0"
tags: [wright, packaging, toml, plans, theseus, authoring]
policy:
  allow_implicit_invocation: true
---

# Wright Plans & Folios Authoring

`wright` is a from-source package manager designed for Linux (specifically Theseus Linux).
This skill provides the standard authoring specifications, styling conventions, and architectural rules derived from `wright` engine architecture and official documentation (`/home/ming/projects/wright/docs/`).

---

## 1. Architectural Principles & Mental Model

```
plan.toml   →  wright build  →  staging/  →  output slicing  →  .wright.tar.zst (parts)
                                                    ↑
                                     [[output]] rules slice staging into parts
```

- **Declarative & No-Magic (ADR-0004)**: All build instructions, source handling, patch applications, and output divisions are explicit. Nothing is inferred or auto-guessed by the engine.
- **Single-Source Staging, Multi-Target Slicing**: The `staging` stage installs all files into a single `${STAGING_DIR}` (`/output` inside isolation). Wright's slicing engine automatically sorts files into separate output parts based on `[[output]]` and `[[discard]]` rules.
- **UsrMerge Standard (ADR-0007)**: Theseus Linux merges `/bin`, `/sbin`, and `/lib` into `/usr`. All executables must be staged into `/usr/bin`, and libraries into `/usr/lib`. Never hardcode `/sbin` or `/lib64`.
- **Single Source of Truth**: `/var/lib/wright/plans/` (or the project plans tree) is the sole authoritative index. Inspect existing plans to verify output names, build dependencies, and compiler flags.

---

## 2. Standard Manifest Layout & Style Conventions

A standard `plan.toml` follows a consistent, sectioned structure:

```toml
# 1. Top-Level Metadata
name = "example"
version = "1.2.3"
release = 1
description = "Concise description of the package"
license = "MIT"
arch = "x86_64"
url = "https://example.com/project"

# 2. Dependencies (Plan-Level)
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

# 4. Pipeline Stages
[pipeline.prepare]
script = '''
cd source/example-${VERSION}
patch -Np1 < ${WORKDIR}/0001-fix-build.patch
'''

[pipeline.configure]
script = '''
cd source/example-${VERSION}
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
'''

[pipeline.compile]
script = '''
cd source/example-${VERSION}
ninja -C build -j$(nproc)
'''

[pipeline.staging]
script = '''
cd source/example-${VERSION}
DESTDIR=${STAGING_DIR} ninja -C build install
'''

# 5. Output Slicing
[[output]]
name = "example"
runtime_deps = ["openssl", "zlib"]

[[output]]
name = "example-dev"
description = "Development headers and pkg-config files"
include = ["/usr/include/**", "/usr/lib/pkgconfig/**"]
```

---

## 3. Style Recommendations & Writing Rules

### A. Source Declarations
- **Hierarchy of Sources**: Prefer `type = "http"` (release tarballs) > `type = "git"` with tagged `ref = "v${VERSION}"` > `type = "git"` with commit hash.
- **Defensive Extraction**: Always set `extract_to = "source"` for main archives so tarballs unpack cleanly.
- **Patches**: Store in `patches/`, declare as `type = "local"`, and do **not** set `extract_to`. Apply manually in `[pipeline.prepare]` using `${WORKDIR}/<patch-name>`.

### B. Dependency Declarations
- **Strict Placement**:
  - `build_deps` (compile-time tools/headers) and `link_deps` (shared ABI libraries) belong **at the plan root**.
  - `runtime_deps` belong **inside `[[output]]` tables**.
- **Naming & References**:
  - Use `plan` for single-output packages (e.g. `"openssl"`).
  - Use `plan:output` for specific outputs of multi-output packages (e.g. `"gcc:gcc-libs"`, `"llvm:clang"`).
  - Use standard version constraints: `["pcre2 >= 10.42"]`.

### C. Pipeline Scripting Best Practices
- **Fail-Fast Shell**: Wright runs scripts with `bash -e -o pipefail`. Write commands cleanly without unnecessary workarounds.
- **Explicit Directory Navigation**: Always start scripts with `cd source/<unpacked-dir-name>`.
- **Atomic File Staging**: Use `install -Dm755 <src> "${STAGING_DIR}/usr/bin/<dst>"` and `install -Dm644 <src> "${STAGING_DIR}/usr/share/<dst>"` instead of fragile `cp`/`chmod` chains.
- **Environment Handling**: Use `[options] env` or stage `env = { ... }` rather than inline `export` commands.

### D. Isolation Level Matrix
- **`strict` (Default)**: C/C++, CMake, Meson, Autotools (fully sandboxed, no network).
- **`relaxed`**: Rust `cargo`, Go `go build`, Node.js `npm`, Python `pip` (when fetching packages over network).
- **`none`**: Use only as a last resort when container namespaces cannot be created.

### E. Output Slicing & Discard Discipline
- **Mutual Exclusivity**: Ensure non-catch-all `[[output]]` patterns do not collide.
- **Discards**: Use `[[discard]]` for deliberately unpackageable files (e.g. `/usr/share/info/**`, `.la` files) and always provide a human-readable `reason`.

### F. Versioning Protocol
- `version`: Matches upstream string.
- `release`: Increments for downstream modifications (patches, build options). **Resets to `1` when `version` is bumped**.
- `epoch`: Defaults to `0`. Bump only if upstream alters numbering schemes so that new versions sort lower.

### G. Circular Dependencies (`mvp.toml`)
- Create `mvp.toml` alongside `plan.toml` to break cycles (e.g. `freetype` ↔ `harfbuzz`).
- Override only `link_deps`/`build_deps` and minimal `pipeline` stages in `mvp.toml`.

---

## 4. Verification Workflow

When `wright` CLI is available on the system:
```bash
# 1. Lint manifest syntax and dependency graph
wright lint <plan-name>

# 2. Fetch and populate SHA256 checksums
wright build <plan-name> --checksum

# 3. Test isolated build and output slicing
wright build <plan-name>
```

---

## 5. Detailed Reference Guides

Load these references on demand:
- **`references/plan-style-guide.md`**: Complete style guide, UsrMerge conventions, and best practices.
- **`references/plan-schema.md`**: Exhaustive field definitions, variables, and validation rules.
- **`references/plan-examples.md`**: Annotated plan templates for Autotools, CMake, Ninja, Cargo, Go, multi-output libraries, and Folios.
