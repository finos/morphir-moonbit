# Workbench MCK adapter

This component exposes the shipped `finos/morphir-execution` value decoder to the
shared Rust MCK's proposed Workbench codec contract `0.1.0-draft.1`. It has no
goldens, evaluator or separate conformance runner. The parent `finos/morphir`
repository owns the corpus and calculates qualification.

`protocol.mbt` handles capability/decode requests and echoes correlation IDs.
JSON input calls `Value::from_json`; Ion text calls the Ion parser and
`Value::from_ion`. Both return `Value::to_json` without a lossy number or Unicode
string conversion. Rejections use the `execution.Invalid` code before the first
colon, omitting input paths and names from bounded observations. Malformed Ion
text uses `workbench.invalid_ion`. The parent transport's `exit` message closes
stdout without an observation. Each Node/native launcher bounds line input at
2 MiB before parsing; the parent bounds value inputs and process supervision.

Only `decode-value` with `json` and `ion-text` is advertised. A successful model
error is a codec outcome projection, without declared argument admission. The
engine still validates types, constructor registries and argument model errors
before evaluation. No connected-host protocol extension is enabled here.

From this repository's root, select a built parent runner and its offline corpus:

```sh
MORPHIR_MCK_BIN=/path/to/finos/morphir/target/debug/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck \
mise run test:workbench-mck
```

The gate builds and qualifies Node/native debug and release adapters, checks the
saved reports through the parent command, and writes evidence beneath
`.dev/workbench-mck/`. The shared pure protocol tests run on JS, native, Wasm and
Wasm GC. Wasm/browser process adapters, Ion binary and reverse encoding remain
pending. No upstream checkout, model or toolchain is downloaded by the gate.
