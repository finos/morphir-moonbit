# Morphir CLI

The Morphir CLI is written in MoonBit. It can run as a native executable, a
WASI module, or JavaScript. The npm package `@morphir/morphir` distributes the
JavaScript build as the `morphir` command.

The initial executable displays a usage message. Morphir commands will be added
as the libraries in `pkgs/` are implemented.

## Run from source

From the repository root:

```sh
mise exec -- moon run apps/morphir --target native
mise exec -- moon run apps/morphir --target js
mise exec -- moon run apps/morphir --target wasm
mise exec -- moon run apps/morphir --target wasm-gc
```

## Targets

| Target | Build command from the repository root | Runtime |
|--------|----------------------------------------|---------|
| Native | `mise run build:native` | Standalone executable for the build machine's OS and architecture |
| JavaScript | `mise run build:js` | Node.js, including npm installation |
| Wasm | `mise run build:wasi` | WASI Preview 1 host or `moonrun` |
| Wasm GC | `mise run build:browser` | `moonrun`, or a Wasm GC host providing `spectest.print_char` |

`mise run build` includes all four targets. Native release builds require a C
compiler. Build on each target platform to produce its native executable.

The native release executable is
`_build/native/release/build/morphir/morphir/morphir.exe` relative to the repository
root. MoonBit uses the `.exe` suffix on macOS and Linux as well as Windows.
It runs without Node.js, npm, or the MoonBit toolchain.

The current Wasm CLI only imports WASI `fd_write`. The smoke tests instantiate it
with Node's WASI Preview 1 host to check that it runs without MoonBit-specific
imports. Wasm GC needs a host adapter for output; it is not a standalone browser
application. Future filesystem, argument, and process APIs must preserve these
runtime requirements or supply adapters for each target.

MoonBit's experimental `llvm` target is not part of this support matrix.

## Build the npm package

With the repository's mise tools active:

```sh
cd apps/morphir
npm run build
npm start
npm pack
```

Building requires MoonBit and Node.js. The packaged executable runs on Node.js
without the MoonBit toolchain. `npm pack` rebuilds the JavaScript before packaging.

## Verify target support

```sh
mise run test:cli
```

This runs the CLI on all four targets, executes the native binary and WASI module
outside the repository, and packs and installs the npm package in a temporary
directory. `mise run test` includes these checks. CI runs them for each target.
