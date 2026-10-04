# Workbench MCK adapter

This component exposes the shipped `finos/morphir-execution` value codec and
validator to the shared Rust MCK. It supports exact contracts
`0.1.0-draft.1` and `0.1.0-draft.2`. It has no goldens, evaluator or separate
conformance runner. The parent `finos/morphir` repository owns the specification,
corpora and verdict calculation. Draft.2 is a local contribution awaiting review.

`protocol.mbt` handles capabilities and `decode-value`, echoes correlation IDs
and rejects unknown/duplicate JSON members. Draft.1 capabilities and its original
64-case corpus remain unchanged. JSON calls `Value::from_json`; Ion text calls
the Ion parser and `Value::from_ion`. Both return `Value::to_json`, preserving
exact numbers, Float64 bits and UTF-16 units. Successful decode of a model error
is an outcome projection, without argument admission.

Draft.2 also supports `validate-value` in both formats. Its `input` has exactly
`value`, `type` and `definitions`. `value` is tagged JSON or a single Ion text
value according to `format`. The type and registry use JSON descriptors matching
`ValueType::to_json` and the generated constructor definitions:

```json
{"value":{"type":"int","value":"9007199254740993"},
 "type":{"type":"int"},"definitions":[]}
```

`admission.mbt` parses closed declarations before decoding the value and calling
the shipped `validate_as`. Every custom owner referenced anywhere in the graph
must be declared, including dormant Maybe/Result branches and unused definitions.
Named recursion is allowed without expanding declarations. Function types are
rejected throughout the graph. Record-field, definition and constructor names
must be unique within their containing declaration. A top-level model error is
forbidden as an argument; ordinary `Result.Err` values remain admissible.
Successful admission returns the canonical value projection, without evaluation.

The complete compact input envelope is limited to 1 MiB of UTF-8 JSON. Type
parsing allows depth 64 and 10,000 aggregate nodes, counting type descriptors,
record-field descriptors, registry definitions and constructors. Registries allow
256 definitions, 256 constructors per definition and 64 inputs per constructor;
tuples and records allow 1,024 entries. Identities allow 1–1,024 UTF-16 units.
Value codec/type validation retains its separate existing budgets. The wire's
127-container JSON framing limit can be stricter than logical type depth.

Malformed declarations use `workbench.invalid_type` or
`workbench.invalid_definitions`; declaration budget violations use
`workbench.type_limit`; excess input bytes use `workbench.input_limit`.
Unresolved custom references and function boundaries use the existing
`execution.unresolved_custom_type` and `execution.boundary_function` codes.
Execution diagnostics retain only the code before the first colon. Malformed
Ion uses `workbench.invalid_ion`. Exit closes stdout without an observation.
Node/native launchers bound input lines at 2 MiB; the parent owns deadlines,
process supervision and report rechecking.

From the repository root, select a built parent runner and its offline corpus:

```sh
MORPHIR_MCK_BIN=/path/to/finos/morphir/target/debug/morphir \
MORPHIR_WORKBENCH_KIT=/path/to/finos/morphir/spec/workbench/mck/draft.2 \
mise run test:workbench-mck
```

Choose `spec/workbench/mck` to requalify the unchanged draft.1 corpus. The gate
builds Node/native debug and release adapters, rechecks every saved report through
the parent command and writes evidence beneath `.dev/workbench-mck/`. Pure
protocol tests run on JS, native, Wasm and Wasm GC. No upstream checkout, model or
toolchain is downloaded. This slice does not qualify public-entry manifests,
invocation arity, output model errors, evaluation, SDK comparison, Ion binary or
reverse encoding, and advertises no connected-host protocol extension.
