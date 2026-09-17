# plan examples — annotated

Skim these to pick the right structure for a given piece of software. Each
example has comments explaining *why* it's shaped that way. Adapt, don't copy
verbatim — every upstream is different.

## Table of contents

1. [Minimal plan (default output)](#1-minimal-plan-default-output)
2. [Real-world plan: nginx (explicit single output, hooks, backup)](#2-real-world-plan-nginx)
3. [Library + development headers (split output, catch-all)](#3-library--development-headers)
4. [Multi-output meta-part with sub-parts](#4-multi-output-meta-part-with-sub-parts)
5. [Explicit discard for ignored files](#5-explicit-discard-for-ignored-files)
6. [Circular dependency: freetype/harfbuzz MVP](#6-circular-dependency-freetypeharfbuzz-mvp)
7. [Rust crate under relaxed isolation](#7-rust-crate-under-relaxed-isolation)
8. [Folio manifest](#8-folio-manifest)
9. [Detecting how the build works (Makefile → plan shape)](#9-detecting-how-the-build-works-makefile--plan-shape)

---

## 1. Minimal plan (default output)

The simplest shape: no `[[output]]` at all. Everything in `${STAGING_DIR}`
becomes one part named after `name`.

```toml
name = "hello"
version = "1.0.0"
release = 1
description = "Hello World test part"
license = "MIT"
arch = "x86_64"

# No sources needed — the source is generated inline in prepare.
[pipeline.prepare]
script = """
cat > hello.c << 'EOF'
#include <stdio.h>
int main() { printf("Hello, wright!\n"); return 0; }
EOF
"""

[pipeline.compile]
script = """
gcc -o hello hello.c
"""

# staging installs into ${STAGING_DIR}; with no [[output]] the whole
# staging dir becomes the "hello" part.
[pipeline.staging]
script = """
install -Dm755 hello ${STAGING_DIR}/usr/bin/hello
"""
```

**When to use:** trivial single-binary software, or anything that produces
exactly one part with no hooks/relations/backup needs.

---

## 2. Real-world plan: nginx

Explicit single output (one `[[output]]`) because it needs conflicts, backup
files, runtime deps, and install hooks. Plus a second output for docs.

```toml
name = "nginx"
version = "1.25.3"
release = 1
description = "High performance HTTP and reverse proxy server"
license = "BSD-2-Clause"
arch = "x86_64"
url = "https://nginx.org"
maintainer = "Example Maintainer <maintainer@example.com>"

# link_deps: shared libs the binary actually links against. Triggers
# rebuild when these update (ABI sensitivity). Version constraints
# follow the output ref.
link_deps = ["openssl", "pcre2 >= 10.42", "zlib >= 1.2"]

# Main archive: ALWAYS extract_to = "source". Build scripts then cd
# into the inner nginx-${VERSION} dir.
[[sources]]
type = "http"
url = "https://nginx.org/download/nginx-${VERSION}.tar.gz"
sha256 = "a51897b1e37e9e73e70d28b9b12c9a31779116c15a1115e3f3dd65291e26bd83"
extract_to = "source"

# A patch: type = "local", NO extract_to (lands directly in ${WORKDIR}).
[[sources]]
type = "local"
path = "patches/fix-headers.patch"

[options]
static = false
debug = false
ccache = true

# prepare applies patches with an explicit strip level. Note ${WORKDIR}
# is used, not a relative path.
[pipeline.prepare]
script = """
patch -Np1 < ${WORKDIR}/fix-headers.patch
"""

[pipeline.configure]
env = { CFLAGS = "-O2 -pipe" }
script = """
./configure --prefix=/usr
"""

[pipeline.compile]
script = """
make -j$(nproc)
"""

[pipeline.check]
script = """
make test
"""

[pipeline.staging]
script = """
make DESTDIR=${STAGING_DIR} install
"""

# Explicit single output — [[output]] is array-of-tables even for one.
# name omitted would default to plan.name ("nginx"); shown for clarity.
[[output]]
name = "nginx"
conflicts = ["apache"]          # mutual exclusion, bidirectional
runtime_deps = ["openssl", "pcre2 >= 10.42", "zlib >= 1.2"]
backup = ["/etc/nginx/nginx.conf", "/etc/nginx/mime.types"]

[output.hooks]
pre_install  = "echo 'Preparing nginx installation...'"
post_install = "useradd -r nginx 2>/dev/null || true"
post_upgrade = "systemctl reload nginx 2>/dev/null || true"
pre_remove   = "systemctl stop nginx 2>/dev/null || true"

# A second output for docs, carved out by include glob. Everything else
# is claimed by the "nginx" output above (which has no include, so it
# acts as the catch-all here).
[[output]]
name = "nginx-doc"
description = "Nginx documentation files"
include = ["/usr/share/doc/**"]
```

**Key points:** `link_deps` at top level (build/link are plan-level);
`runtime_deps` inside the output (output-level only); the catch-all output
(`nginx`) has no `include`; the docs output carves `/usr/share/doc/**`.

---

## 3. Library + development headers

Split runtime libraries from headers and static archives. This is the most
common multi-output pattern. `libfoo` is the catch-all (no `include`), keeping
whatever `libfoo-dev` doesn't claim.

```toml
name = "libfoo"
version = "1.0.0"
release = 1
description = "Foo library"
license = "MIT"
arch = "x86_64"

[pipeline.staging]
script = """
make DESTDIR=${STAGING_DIR} install
"""

# Runtime libs — catch-all. No include => keeps everything not claimed
# by libfoo-dev. runtime_deps live here because they're output-level.
[[output]]
name = "libfoo"
description = "Foo runtime libraries"
include = ["/usr/lib/libfoo.so*"]
runtime_deps = ["glibc"]

# Dev files — carved out by specific globs. description required.
[[output]]
name = "libfoo-dev"
description = "Foo development files"
include = ["/usr/include/**", "/usr/lib/libfoo.a", "/usr/lib/pkgconfig/libfoo*"]
```

**Why this works:** every staged file is either a `.so*` (claimed by `libfoo`),
a header/`.a`/pkgconfig (claimed by `libfoo-dev`), or a leftover caught by the
catch-all. Slicing can't fail.

---

## 4. Multi-output meta-part with sub-parts

A meta-part that depends on all sub-parts, useful for grouping (e.g. firmware
split by vendor). The meta-part has no files; sub-parts claim everything.

```toml
name = "linux-firmware"
version = "20250101"
release = 1
description = "Linux firmware files"
license = "multiple"
arch = "x86_64"

# Meta-part: depends on all sub-parts via runtime_deps, has NO include
# and NO files of its own (sub-parts claim everything).
[[output]]
name = "linux-firmware"
runtime_deps = ["linux-firmware-amd", "linux-firmware-intel", "linux-firmware-nvidia"]

[[output]]
name = "linux-firmware-amd"
description = "AMD GPU/CPU firmware"
include = ["/usr/lib/firmware/amdgpu/**", "/usr/lib/firmware/radeon/**"]

[[output]]
name = "linux-firmware-intel"
description = "Intel GPU/CPU firmware"
include = ["/usr/lib/firmware/i915/**", "/usr/lib/firmware/iwlwifi/**"]

[[output]]
name = "linux-firmware-nvidia"
description = "NVIDIA GPU firmware"
include = ["/usr/lib/firmware/nvidia/**"]
```

---

## 5. Explicit discard for ignored files

When staging produces files you neither package nor want caught by a catch-all,
discard them explicitly with a reason.

```toml
name = "llvm-tools"
version = "22.1.3"
release = 1
description = "Selected LLVM tools"
license = "Apache-2.0-with-LLVM-exception"
arch = "x86_64"

[[output]]
name = "llvm-opt"
description = "LLVM optimizer"
include = ["/usr/bin/opt", "/usr/bin/llvm-opt*"]

[[output]]
name = "llvm-dis"
description = "LLVM disassembler"
include = ["/usr/bin/llvm-dis", "/usr/bin/llvm-as"]

# Discard is always array-of-tables; each rule needs include + reason.
[[discard]]
include = [
    "/usr/share/doc/**",
    "/usr/share/man/**",
]
reason = "documentation and manual pages are intentionally not packaged"
```

---

## 6. Circular dependency: freetype/harfbuzz MVP

fretype and harfbuzz have a genuine build cycle. An `mvp.toml` breaks it by
omitting the cyclic dep in the first pass. wright detects the cycle (Tarjan SCC)
and inserts a two-pass schedule automatically.

**`freetype/plan.toml`** (full build, with harfbuzz):
```toml
name = "freetype"
version = "2.13.2"
release = 1
description = "FreeType font rendering library"
license = "FTL OR GPL-2.0-or-later"
arch = "x86_64"

link_deps = ["harfbuzz", "freetype"]

[[sources]]
type = "http"
url = "https://downloads.sourceforge.net/freetype/freetype-${VERSION}.tar.xz"
sha256 = "..."
extract_to = "source"

[pipeline.configure]
script = """
cd source/freetype-${VERSION}
./configure --prefix=/usr --with-harfbuzz
"""

[pipeline.staging]
script = """
cd source/freetype-${VERSION}
make DESTDIR=${STAGING_DIR} install
"""
```

**`freetype/mvp.toml`** (bootstrap pass, without harfbuzz — breaks the cycle):
```toml
link_deps = ["freetype"]

[pipeline.configure]
script = """
cd source/freetype-${VERSION}
./configure --prefix=/usr --without-harfbuzz
"""
```

---

## 7. Rust crate under relaxed isolation

Rust's cargo fetches from crates.io during build, so use `relaxed` isolation
(unless deps are vendored, in which case `strict` works).

```toml
name = "ripgrep"
version = "14.1.0"
release = 1
description = "Recursively search directories for a regex pattern"
license = "Unlicense OR MIT"
arch = "x86_64"

[[sources]]
type = "http"
url = "https://github.com/BurntSushi/ripgrep/archive/refs/tags/${VERSION}.tar.gz"
sha256 = "..."
extract_to = "source"

[pipeline.compile]
isolation = "relaxed"
script = """
cd source/ripgrep-${VERSION}
cargo build --release --frozen
"""

[pipeline.staging]
isolation = "relaxed"
script = """
cd source/ripgrep-${VERSION}
install -Dm755 target/release/rg ${STAGING_DIR}/usr/bin/rg
install -Dm644 doc/rg.1 ${STAGING_DIR}/usr/share/man/man1/rg.1
"""
```

---

## 8. Folio manifest

A folio names many plans that form a system. Live in `folios/`, a *peer* of
`plans/`. Used by `wright launch`.

```toml
[folio]
name        = "desktop"
version     = "1"
description = "Wayland-based desktop system"

plans = [
    # Core
    "glibc", "bash", "coreutils", "util-linux",
    # Networking
    "openssl", "curl", "wget",
    # Graphics
    "mesa", "libdrm", "libinput",
    # Desktop
    "sway", "foot", "firefox",
]

[[provide]]
name    = "linux"
version = "6.12.0"

[[hook]]
stage  = "post-launch"
script = """
echo "wright-desktop" > $ROOT/etc/hostname
ln -sf ../usr/share/zoneinfo/UTC $ROOT/etc/localtime
echo "LANG=en_US.UTF-8" > $ROOT/etc/locale.conf
"""
```

---

## 9. Detecting how the build works (Makefile → plan shape)

What to extract from a `Makefile` or build configuration:

1. **The build command** — scan `.PHONY:` aliases and the output-rule targets.
2. **The install layout** — `DESTDIR=$(STAGING_DIR) install` defines your staging layout. If there is no install target, stage manually in `[pipeline.staging]` with `install -Dm...`.
3. **Required build tools** — Compiler/build system requirements (`build_deps`).
4. **Linked libraries** — `pkg-config --libs` / `-l` flags (`link_deps`).
5. **Output shape** — Self-contained binary (with embedded assets) vs separately-shipped runtime files.
