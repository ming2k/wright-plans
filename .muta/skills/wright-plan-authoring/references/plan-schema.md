# plan.toml — complete schema reference

Exact types, defaults, and required-ness for every field. Consult this when you
need to know whether a field is optional or what its default is. Condensed from
wright's `docs/reference/plan-manifest.md`.

## Table of contents

1. [Top-level metadata](#1-top-level-metadata)
2. [Version policy](#2-version-policy)
3. [Plan-level dependencies](#3-plan-level-dependencies)
4. [Sources (`[[sources]]`)](#4-sources-sources)
5. [Options (`[options]`)](#5-options-options)
6. [Pipeline stages (`[pipeline.<stage>]`)](#6-pipeline-stages-pipelinestage)
7. [Stage order (`[pipeline_order]`)](#7-stage-order-pipeline_order)
8. [Outputs (`[[output]]`)](#8-outputs-output)
9. [Discards (`[[discard]]`)](#9-discards-discard)
10. [Install hooks (`[output.hooks]`)](#10-install-hooks-outputhooks)
11. [Variable substitution](#11-variable-substitution)
12. [Isolation levels](#12-isolation-levels)
13. [Validation rules](#13-validation-rules)
14. [Archive filename format](#14-archive-filename-format)
15. [MVP overrides (`mvp.toml`)](#15-mvp-overrides-mvptoml)

---

## 1. Top-level metadata

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | string | yes | — | Part name. Must match `[a-z0-9][a-z0-9_+.-]*`, max 64 chars |
| `version` | string | no | — | Free-form version. Omit for rolling/VCS builds |
| `release` | integer | yes | — | Build revision, must be ≥ 1 |
| `epoch` | integer | no | `0` | Forces ordering when upstream changes versioning scheme |
| `description` | string | yes | — | Must not be empty |
| `license` | string | yes | — | SPDX license identifier |
| `arch` | string | yes | — | Target architecture (e.g. `x86_64`) |
| `url` | string | no | — | Upstream project URL |
| `maintainer` | string | no | — | Maintainer name and email |

## 2. Version policy

| Field | Rule |
|-------|------|
| `version` | Tracks upstream release; keep identical to upstream string when one exists |
| `release` | Increments **within** the same `version` when the plan changes. **Resets to 1 on every version bump** |
| `epoch` | Increments **only** when upstream changes versioning scheme so new version sorts lower (e.g. `2024.1` → `1.0.0`). Never decreases |

### Omitting `version`
- Field absent from `.PARTINFO`
- Archive filename omits version: `{name}-{release}-{arch}.wright.tar.zst`
- Build dir uses `<name>-noversion` suffix
- The part satisfies all version constraints automatically
- `wright list --long` shows `-` for version

## 3. Plan-level dependencies

Top-level fields affecting build planning and `wright resolve`.

| Field | Type | Description |
|-------|------|-------------|
| `build_deps` | list of strings | Build-time deps mounted into isolation (tools, headers) |
| `link_deps` | list of strings | ABI-sensitive linked libs; triggers rebuild on update |

Constraint operators: `>=`, `<=`, `>`, `<`, `=`. Put after the output ref:
`["pcre2 >= 10.42"]`.

Two reference forms:

| Form | Meaning | Example |
|------|---------|---------|
| `plan` | All outputs of `plan` | `openssl` |
| `plan:output` | Exactly one output | `llvm:llvm-libs` |

`wright lint` validates that referenced local plans exist; for `plan:output`
refs it also checks the output is declared by that plan.

> **Pitfall:** bare `clang` means "all outputs of a `clang` plan", not "the
> `clang` output of the `llvm` plan". Use `plan:output` for specific outputs.

Runtime deps are **output-level only** (`runtime_deps` inside each
`[[output]]`). There is no plan-level fallback.

## 4. Sources (`[[sources]]`)

Array-of-tables with a mandatory `type` field.

### `type = "http"`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `url` | string | required | Remote URL (`http://` or `https://`) |
| `sha256` | string | required | SHA-256 checksum. `"SKIP"` only during dev / untrusted sources |
| `as` | string | optional | Filename in source cache *and* `${WORKDIR}`. Cache defaults to `<plan>-<basename>`; WORKDIR defaults to URL basename |
| `extract_to` | string | optional | Subdirectory under `${WORKDIR}` to extract/copy into |

### `type = "git"`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `url` | string | required | Git repo URL |
| `ref` | string | `"HEAD"` | Branch, tag, or commit hash. Supports `${VERSION}` substitution |
| `depth` | integer | `1` | Shallow clone depth. `null`/omit for full clone. Disabled for 40-char commit hashes |
| `extract_to` | string | optional | Subdirectory under `${WORKDIR}` to check out into |

### `type = "local"`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `path` | string | required | Path relative to plan dir; must not escape it |
| `as` | string | optional | Filename in cache and `${WORKDIR}` |
| `extract_to` | string | optional | Subdirectory under `${WORKDIR}` to copy into |

### Archive handling
- Archives with `.tar.gz`, `.tgz`, `.tar.xz`, `.tar.bz2`, `.tar.zst`, `.tar.lz`, `.zip` are auto-extracted during `extract`.
- Non-archives are copied to `${WORKDIR}` (or `extract_to`) under their basename, or under `as` when set.
- The `<plan>-` cache prefix never appears in `${WORKDIR}` (ADR-0024).
- Two sources resolving to the same `${WORKDIR}` file abort the build — rename one with `as`.

## 5. Options (`[options]`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `static` | bool | `false` | Statically linked binaries |
| `debug` | bool | `false` | Build with debug info |
| `ccache` | bool | `true` | Use ccache if available |
| `env` | map<string,string> | `{}` | Env vars injected into every pipeline stage |
| `memory_limit` | integer | — | Max virtual address space per build process (MB). Note: limits virtual address space (`RLIMIT_AS`), not RSS — set generously (2-3x expected) |
| `cpu_time_limit` | integer | — | Max CPU time per process (seconds) |
| `timeout` | integer | — | Wall-clock timeout per stage (seconds). Most important safety net |
| `skip_fhs_check` | bool | `false` | Skip FHS validation after output slicing |

Per-plan values override global (`wright.toml`) settings.

## 6. Pipeline stages (`[pipeline.<stage>]`)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `executor` | string | `"shell"` | Executor to run the script (`shell` built-in, or a custom executor name) |
| `isolation` | string | `"strict"` | Security isolation level (see §12) |
| `env` | map<string,string> | `{}` | Extra env vars (supports variable substitution in values) |
| `script` | string | `""` | The script to execute |

### Default stages

| Stage | Type | Description |
|-------|------|-------------|
| `fetch` | built-in | Download sources, copy local files |
| `verify` | built-in | Verify SHA-256 checksums |
| `extract` | built-in | Extract archives, copy non-archives to `${WORKDIR}` |
| `prepare` | user | Pre-build setup (apply patches) |
| `configure` | user | Run configure scripts |
| `compile` | user | Compile |
| `check` | user | Run test suites |
| `staging` | user | Install files into `${STAGING_DIR}` |

Built-in stages are automatic; user stages run only if defined.

### Pre/Post hooks
Any stage can have `pre_<stage>` or `post_<stage>` tables under `pipeline`.
Order: `pre_<stage>` → `<stage>` → `post_<stage>`. Same fields as a stage.

## 7. Stage order (`[pipeline_order]`)

Override the default order:

```toml
[pipeline_order]
stages = ["fetch", "verify", "extract", "configure", "compile", "staging"]
```

## 8. Outputs (`[[output]]`)

Always array-of-tables, even for a single output. `[output]` singular is not
supported.

| Field | Required | Notes |
|-------|----------|-------|
| `name` | No | Part name for this output. Omit/`""` → use `plan.name` |
| `description` | Yes (non-catch-all) | Human-readable. Not required for catch-all |
| `include` | No | Glob patterns to claim. Omit on ≤1 output to define a catch-all |
| `exclude` | No | Glob patterns to exclude |
| `runtime_deps` | No | Per-output runtime dependencies |
| `hooks.*` | No | Per-output transaction hooks (see §10) |
| `backup` | No | Per-output backup (config) files |
| `replaces` | No | Per-output replacement relations (one-way) |
| `conflicts` | No | Per-output conflict relations (bidirectional) |
| `provides` | No | **Deprecated**, parsed but ignored |
| `arch` | No | Override parent arch (e.g. `any` for docs) |

Sub-parts inherit `version`, `release`, `arch`, `license` from the parent unless overridden.

### Coverage rules
1. Every staged file must be claimed by one `[[output]]`, matched by `[[discard]]`, or caught by the optional catch-all.
2. Unclaimed staged files fail slicing.
3. At most one catch-all allowed.
4. `description` not required for catch-all.

### Slicing rules
1. All non-catch-all `[[output]]` entries evaluated **simultaneously**.
2. A file matches when it hits any `include` and not any `exclude`.
3. **Mutual exclusivity enforced** — a file matching >1 output fails immediately with the conflicting names.
4. Remaining files matching `[[discard]]` are ignored.
5. The catch-all keeps whatever remains.
6. Anything still unclaimed fails slicing.

`[[output]]` order has no effect. Use `exclude` to carve overlaps.

> **Critical:** `include = ["/**"]` on a non-catch-all output greedily captures
> *all* files. Each non-catch-all output should match only its own files.

### Part relations (per-output)

| Relation | Behavior |
|----------|----------|
| `replaces` | On install, silently removes any installed part in this list. One-way (renames/merges) |
| `conflicts` | Mutual exclusion. Install refused while conflicting part present. Bidirectional |
| `provides` | **Deprecated.** Parsed but ignored |

### Backup files
Files in `backup` are treated as user-owned config:
- **On upgrade:** new default written as `<path>.wnew`; live file left intact.
- **On remove:** config files are not deleted.

## 9. Discards (`[[discard]]`)

Use only with `[[output]]` mode. Always array-of-tables.

| Field | Required | Notes |
|-------|----------|-------|
| `include` | **Yes** | Glob patterns to ignore |
| `exclude` | No | Glob patterns to keep out of this discard rule |
| `reason` | **Yes** | Human-readable explanation for ignoring matched files |

## 10. Install hooks (`[output.hooks]`)

Transaction-time scripts run on the **live system**, serially, blocking install.
Keep them fast. They **do not run** during `wright launch`.

| Field | Description |
|-------|-------------|
| `pre_install` | Run before first install |
| `post_install` | Run after first install |
| `post_upgrade` | Run after upgrade |
| `pre_remove` | Run before part removal |
| `post_remove` | Run after part removal |

For slow single-threaded regenerations (font caches, `fmtutil-sys --all`,
`texhash`), run only the subset needed at install time; let the user invoke the
full regen manually.

> During `wright launch` the target root is provisioned from scratch and may not
> be bootable, so plan-level hooks don't run there. Do provisioning in a
> folio-level `[[hook]]` instead.

## 11. Variable substitution

`${VAR}` syntax, expanded in scripts, source URIs, and `extract_to` paths.
Unrecognized variables left as-is.

| Variable | Description |
|----------|-------------|
| `${NAME}` | Current output name |
| `${VERSION}` | Version from `version` (absent if omitted) |
| `${RELEASE}` | Release number as a string |
| `${ARCH}` | Target architecture |
| `${WORKDIR}` | Extraction root dir |
| `${STAGING_DIR}` | Current output staging dir |
| `${MAIN_PART_NAME}` | Primary output name from top-level `name` |
| `${MAIN_STAGING_DIR}` | Primary output staging dir |
| `${WRIGHT_BUILD_PHASE}` | Current phase (`full` or `mvp`) |
| `${WRIGHT_BOOTSTRAP_WITHOUT_<DEP>}` | `1` for each dep excluded in MVP pass |

### Path variables

| Variable | Host value (default) | Isolation value |
|----------|----------------------|-----------------|
| `${WORKDIR}` | `…/workshop/<name>-<version>/work`¹ | `/build` |
| `${STAGING_DIR}` | `…/workshop/<name>-<version>/staging`¹ | `/output` |

¹ `<name>-noversion` when `version` omitted.

Inside isolation: `/build` is a read-write mount of the host build work dir;
`/output` is a read-write mount of the host staging dir. After stages complete,
wright hard-links `staging/` into `outputs/<name>/` per the slicing rules.

## 12. Isolation levels

| Level | Description |
|-------|-------------|
| `none` | No isolation. Runs directly on host |
| `relaxed` | Mount, PID, UTS namespaces. Network + IPC shared with host |
| `strict` (default) | `relaxed` + network + IPC namespaces |

In `relaxed`/`strict`, the isolation pivots to a minimal root filesystem. In
`strict`, wright mounts a pre-copied read-only sysroot as an overlayfs lower
layer with per-task writable upper layers. Both modes bind-mount `/build` and
`/output` read-write, provide `/dev` with basic devices, mount fresh `/proc` and
`/tmp`, set hostname to `wright-isolation`.

If the kernel lacks the required namespaces, falls back to direct execution
with a warning.

## 13. Validation rules

| Rule | Detail |
|------|--------|
| `name` | `[a-z0-9][a-z0-9_+.-]*`, max 64 chars |
| `version` | Optional; if present, non-empty alphanumeric |
| `release` | ≥ 1 |
| `epoch` | ≥ 0 (default 0) |
| `description` | Must not be empty |
| `license` | Must not be empty |
| `arch` | Must not be empty |
| `sha256` | Each `[[sources]]` has its own (`"SKIP"` for local paths and git) |

## 14. Archive filename format

- With version: `{name}-{version}-{release}-{arch}.wright.tar.zst`
- Without version: `{name}-{release}-{arch}.wright.tar.zst`
- With epoch > 0: `{name}-{epoch}:{version}-{release}-{arch}.wright.tar.zst`
  (or `{name}-{epoch}:{release}-{arch}.wright.tar.zst` if version absent)

## 15. MVP overrides (`mvp.toml`)

A sibling file for breaking genuine circular build-time dependencies. Allowed
top-level fields:

- `build_deps`
- `link_deps`
- `pipeline`
- `pipeline_order`

MVP `build_deps`/`link_deps` **override** the top-level plan fields (omitted
fields fall back to `plan.toml`). For pipeline stages: if
`[pipeline.<stage>]` exists in `mvp.toml`, it's used; otherwise falls back to
`plan.toml`.

**Do not** duplicate part metadata, sources, outputs, or hooks in `mvp.toml`.

wright uses Tarjan's SCC to detect cycles; if a cycle is found and an MVP file
removes at least one edge, the two-pass schedule (MVP → full) is inserted
automatically. Can also be triggered manually with `wright build <plan> --mvp`.
