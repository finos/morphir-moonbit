# Morphir Workbench desktop

A Proton 0.3.4 native host for the shared
[MoonBit/Rabbita workbench](../morphir-workbench/README.md). Its own `moon.work`
keeps CEF acquisition out of the portable repository's default checks. The
frontend build copies the browser app and worker into `frontend/dist`; no UI is
forked for desktop.

## Develop

Install the repository's pinned MoonBit and Node toolchains, then:

```sh
moon install moonbit-community/proton_cli@0.3.4
cd apps/morphir-workbench-desktop
moon update
proton_cli cef setup
proton_cli dev
```

The CLI starts the shared browser build and development server before launching
the native window. `proton_cli build -- --release` compiles the host.

## Package

```sh
proton_cli package --dry-run
proton_cli package --release
```

This creates local unsigned artifacts under `_build/package`; it does not
publish a release. CLI, framework and CEF helper versions must match. Supported
Proton source-built platforms are macOS Apple Silicon, Linux x64 and Windows
x64. This slice's actual desktop verification is on macOS Apple Silicon.

The packaged frontend uses Proton's secure application asset origin and runs
the same worker-based local pipeline. Native engine/process integration and
attachment to an authenticated Morphir daemon are later adapter work. The
browser's Connect link requires a host serving these assets on the same origin;
it does not turn the packaged application origin into a daemon connection.

For a headless packaged-app smoke check, enable Proton's CDP port using
`PROTON_REMOTE_DEBUGGING_PORT` and `PROTON_HEADLESS=1`, then run the browser
package's `scripts/desktop-test.js <cdp-url>`. Keep that debugging port confined
to local development.
