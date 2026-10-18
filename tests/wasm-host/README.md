# Wasm host qualification

This opt-in suite builds a real component from MoonBit source and WIT. It supplies
repeatable evidence for `morphir-ukvn.5.55.7` before we choose the portable MEP
adapter. The fixture's `morphir:host-probe` interface is a test contract. It is not
a new MEP binding or a capability advertised by the CLI.

Run from the repository root:

```console
mise run setup:wasm-hosts
mise run test:wasm-hosts
```

Setup installs the frozen test dependencies and Chromium. The check acquires
released tools through mise, generates bindings beneath `.dev/`, builds the
MoonBit guest, validates/packages it, invokes the component in Wasmtime, and
tests jco's generated bindings in Node and Chromium. It does not build Rust.
This task is not added to routine CLI CI or the installed qualification gate.

| Tool | Pin |
| --- | --- |
| MoonBit | `0.10.15+943464bfa`, repository toolchain |
| wit-bindgen | `0.63.0` |
| wasm-tools | `1.259.0` |
| Wasmtime | `49.0.3` |
| jco | `1.39.0`, frozen Bun lockfile |
| Playwright | `1.64.1`, frozen Bun lockfile |

The generated canonical ABI uses UTF-16, matching MoonBit strings. Generated
bindings are rebuilt from `probe.wit`; `guest.mbt` replaces their implementation
stub. Generated files and reports remain beneath `.dev/wasm-host-qualification/`.

## What the checks establish

| Route | Checks |
| --- | --- |
| Wasmtime CLI, reference host | MoonBit-produced component loads; a record containing Unicode, an enum and Ion binary bytes returns through `result`. |
| jco bindings in Node and Chromium | Non-BMP/combining/NUL text; empty, 64 KiB and arbitrary byte lists; exact Ion and explicit JSON bytes; retained output after subsequent calls and canonical post-return; 105 accepted calls; typed refusal and recovery; idempotent application close; closed result; fresh instance isolation; trap isolation. |
| Node worker | A ready component enters an infinite loop; terminating its worker completes with the expected exit. |
| Chromium worker | A ready component enters an infinite loop; the host requests worker termination and a fresh instance works. Browser workers do not expose an exit acknowledgement. |
| Existing production embedding API, Node and Chromium | Direct component input is rejected with `WebAssembly.CompileError`. It remains a core-Wasm API; jco hosting is not already integrated into it. |

The Ion fixture is a valid IVM plus integer 42. This test transports bytes; it does
not validate or evaluate a MorphirModel. JSON remains explicitly supported and
receives its own byte-preservation case. These tests do not establish MEP
negotiation, compile/generate behavior, resource handles, host callbacks, memory
leak freedom, sandbox enforcement, or production Workbench/Proton integration.
Worker termination is host isolation/cancellation, not component-level interruption.

## Optional native MoonBit embedding

Supply an explicit Wasmoon checkout at
`5490d6bf1cc293c1a3adc42dd3583e607b1ec631`:

```console
MORPHIR_WASMOON_CHECKOUT=/absolute/path/to/wasmoon mise run test:wasm-hosts
```

The suite creates its own workspace referencing that checkout's modules. It does
not clone dependencies, edit the checkout or install a probe inside it. Upstream
native build prerequisites must already work. In the local study, its Python
prebuild selected system Python 3.9; an explicit Python 3.14.7 build-rule path
was needed. The report records the checkout's tracked diff, so such a local
change stays visible. Native runtime semantics were not patched.

The native interpreter checks Unicode/Ion bytes, 101 repeated calls, argument
type refusal, closed result, fresh instance state, an infinite loop stopped by
an execution budget, and refusal after runtime destruction. It does not run the
entire Node/browser case set. An omitted checkout is recorded as `not-run`.

## Evidence and next use

`run.ion` records versions and completed host results. Its spelling is JSON,
which is valid Ion text; the individual JS reports intentionally use JSON for
JavaScript test tooling. Node records the input component's SHA-256. The old
completion record is removed before each run, and a failed run does not publish
a new one. Logs and individual reports may still exist after a failed run.

The test contract separates tool acquisition from component invocation. `moonx`
can supply a process ToolHost for registry tools and `.mbtx` scripts. An Extism
adapter can reuse the official C/JS SDKs. Neither route is implicitly qualified
by this component fixture. Their separate study evidence lives in the design of
`morphir-ukvn.5.55.7`.

Next qualification should exercise host imports and owned/borrowed resources,
then actual MEP model operations through the chosen production adapter. Keep
per-host evidence and capability claims separate.
