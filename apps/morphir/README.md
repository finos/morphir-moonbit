# Morphir CLI

The CLI discovers Morphir workspaces, resolves TOML configuration, runs Scheme/IR pipelines and publishes artifacts through a host adapter.

## Run from this repository

```sh
mise exec -- moon run apps/morphir --target native -- run path/to/workspace --all
mise exec -- moon run apps/morphir --target js -- workspace path/to/workspace --json
```

Or build and run a standalone executable:

```sh
mise exec -- moon build apps/morphir --target native --release
./_build/native/release/build/morphir/morphir/morphir.exe run path/to/workspace --all
```

## npm package

```sh
mise exec -- npm --prefix apps/morphir run build
node apps/morphir/bin/morphir.js --help
node apps/morphir/bin/morphir.js run path/to/workspace --all
```

The package is named `@morphir/morphir`. After installing a packed or published package, invoke `morphir`. Installation does not require the MoonBit toolchain.

## WASM and WASM-GC

```sh
mise exec -- moon build apps/morphir --target wasm --release
node pkgs/morphir-host/runners/wasm.mjs \
  _build/wasm/release/build/morphir/morphir/morphir.wasm run path/to/workspace --all
```

For WASM-GC, change both target/path occurrences from `wasm` to `wasm-gc`. WASI uses only Preview 1 imports and preopens the current directory; discovery cannot ascend outside that preopen. WASM-GC uses the documented `morphir_host_v1` embedding interface. See [host adapters](../../pkgs/morphir-host/README.md) for configuration mounts and runtime details.

## Commands

```sh
morphir workspace [path] --json
morphir run [path] --project Core
morphir run [path] --project packages/core
morphir run [path] --all
morphir run path/to/file.scm --file
morphir run path/to/source-directory --directory
morphir run [path] --config transforms.scm --backend scheme
morphir run [path] --dry-run
```

Paths are relative to the current directory. Without a selection, the CLI chooses the enclosing member, configured default member, root project or sole member. A workspace with several members and no default requires `--project` or `--all`. A file path selects only that file. A directory within a project's sources selects that directory; `--directory` explicitly selects a directory even if it is a project root.

Options include `--frontend`, `--backend`, `--output`, `--config`, `--json` and `--dry-run`. Dry run resolves scripts and prints planned sources/destinations without reading source contents or publishing outputs. Exit statuses are 0 success, 2 invalid invocation/configuration, 1 execution/publication failure and 130 cancellation.

## Workspace example

```toml
[workspace]
members = ["packages/*"]
exclude = ["packages/experimental"]
default_member = "packages/core"
out_dir = ".morphir/out"

[frontend]
language = "scheme"

[ir]
format_version = 4
```

A member's `packages/core/morphir.toml`:

```toml
[project]
name = "Core"
source_directory = "src"
```

The CLI also finds `.morphir/morphir.toml` and `.config/morphir/config.toml`. Multiple primary candidates are errors. YAML candidates are detected and reported as unsupported. Legacy `morphir.json` and `morphir-workspace.json` remain supported; canonical configuration takes precedence with a warning.

Configuration layers are defaults, system, global user, workspace primary, member primary, workspace/member user overrides, environment and CLI. Global configuration and shared workspace defaults exclude project identity and workspace-root settings when applied to a member. Tables merge recursively and arrays replace. TOML encoding preserves unknown values semantically, without preserving comments or formatting.

Workspace and project `morphir.config.scm` files supply pipeline configuration and transforms. An explicit `--config` script runs last; explicit CLI frontend/backend choices are reapplied afterward. Scripts cannot access filesystem, processes or network implicitly.

Outputs go to `.morphir/out/<member-path>/compile.dest/<source-stem>.ir.json`. Each source produces an independent distribution. Project-wide linking and dependency resolution are separate compiler work. Supported frontends/backends are `scheme` and `ir-json`; requested unregistered frontends fail explicitly. JSON output supports IR versions 1 through 4 through existing lossless migration codecs. Unsupported layouts and serialization formats fail validation.

Conventional project/module spelling such as `Core` and `Main.scm` is converted to canonical IR names. `project.module_prefix` qualifies modules; `project.exposed_modules` controls module visibility.

No outputs are published if any selected project's transformation fails. A publication I/O failure can leave earlier task destinations committed; the JSON result identifies them. See the host documentation for locking and recovery.

## Tests

```sh
mise run test:cli
```

Tests run real workspaces on native, Node, standalone WASI and WASM-GC, then pack/install the npm package and repeat the workflow.
