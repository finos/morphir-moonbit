# Morphir MoonBit generator

`finos/morphir-moonbit` generates a MoonBit library from current typed Morphir IR.
It has no engine, host, filesystem, process or network imports. `generate(Input)`
returns its own `Output`, containing a project description, source/manifests,
symbols and Ion metadata. Compilation and publication belong to host stages.

This first slice supports complete library distributions with zero-input scalar
declarations, scalar literals, Unit and references to other zero-input values.
It flattens Morphir modules into one MoonBit package. Type aliases, custom types,
input parameters, applications, closures, records and collections are subsequent
work. Unsupported constructs, incomplete bodies, unregistered native/external
implementations, ambiguous types and contradictory inferred types fail with a
`GenerationError` carrying code, node context and detail. It emits no placeholders.

## Contracts and output

```moonbit
let input = @generator.Input::new("pricing", current_ir)
let output = @generator.generate(input)
```

`Input` carries a unit ID, current `IRFile`, node metadata and ordered annotation
tokens. Applications adapt their boundary types to this contract. The engine's
codec conformance tests exercise JSON, Ion text and Ion binary inputs against the
same generator without adding an engine dependency to the generator.

| Artifact | Purpose |
| --- | --- |
| `moon.mod` | Native module manifest with the SDK module requirement |
| `moon.pkg` | Only the scalar SDK imports used by the generated code |
| `library.mbt` | Deterministic flattened declarations |
| `symbols.10n` | Binary Ion symbols, source identities, origins and metadata |

`Project` records the generated module name, relative root, artifact membership
and semantic dependency requirements. These requirements do not prove dependency
resolution or a successful build. The generated module name and declaration names
hex-encode validated canonical names. They preserve case, initialisms, word
boundaries, package paths and module paths. Public values in public modules produce
`pub fn`; other declarations stay private. Cross-module references require public
source declarations even though the generated package is flat.

Zero-input values become accessor functions, preserving evaluation on reference
without eager global initialization. Each accessor can propagate `SdkError`.

## Scalar mapping and audited imports

| Morphir type | MoonBit type and construction |
| --- | --- |
| `morphir/SDK:basics#int` | `integer.Integer`, constructed from the exact lexeme with `integer.parse` |
| `morphir/SDK:basics#float` | `Double`, constructed from its IEEE bits, including negative zero and subnormals |
| `morphir/SDK:basics#bool` | `Bool` |
| `morphir/SDK:string#string` | `sdk.Text`, constructed from UTF-16 code units |
| `morphir/SDK:char#char` | `sdk.Character`, constructed from UTF-16 code units |
| `morphir/SDK:decimal#decimal` | `decimal.Decimal`, constructed after exact coefficient/exponent validation |
| Unit | `Unit` |

The scalar construction APIs are audited against this repository's SDK source.
This slice does not implement the SDK's 248 value bindings. References to SDK
values fail until an explicit binding is implemented. The required SDK manifest
version is `0.1.0`, API profile `morphir-sdk-scalars-v1`, with semantic inventory pin
`bc99af69a8b24d391311fae3822a87eafef3c334`. Hosts must identify the actual supplied
source separately from that version.

Integer construction never narrows through a machine Int or Float. Decimal
construction normalizes an explicit numerical spelling while retaining the
original IR lexeme in metadata. It rejects nonzero precision below the SDK's
minimum exponent of -32 and bounds explicit exponents to -10000 through 10000.
Numerical Decimal normalizes zero and trailing zeros according to SDK behavior;
the source lexeme and rich Ion metadata retain their original spelling and scale.
Nonfinite Float literals and document literals are unsupported.

## Node identities and Ion preservation

The `morphir-moonbit-symbols-v1` profile has annotation `morphir_moonbit_symbols`.
It records source annotation tokens in order, retained rich metadata, source node
IDs and generated symbols. A symbol's generated declaration is derived from its
source declaration and body. Stable source IDs for this slice are:

- `unit:<unit-id>`
- `module:<package>:<module>`
- `value:<package>:<module>#<name>`
- The value ID followed by `/output` or `/body`

Metadata must reference a known ID exactly once. Unknown or duplicate IDs fail
preservation checks. Metadata values remain native Ion values, preserving ordered
unknown annotations and rich data. A canonical current Morphir JSON snapshot in
`source_ir_json` retains semantic IR attributes, extensions, documentation and
literal lexemes as an explicit compatibility record within the Ion artifact.
Rich Ion metadata never passes through that JSON record.

Generation defaults to 10,000 declarations and 4 MiB of total artifacts. These
are acceptance budgets for trusted typed input, not allocation or streaming
parser guarantees. A cancellation callback is checked between declarations and
before returning artifacts.

## Validation

```sh
mise exec -- moon test -p finos/morphir-moonbit \
  -p finos/morphir-engine/data/generator-conformance --target all
MOON_HOME="$HOME/.moon" mise exec -- node \
  pkgs/morphir-moonbit/scripts/test-compiler.mjs pkgs/morphir-sdk
```

`MOON_HOME` must identify a complete installation containing compiler and core
version `0.10.14+7d59c7ec9`. The SDK argument supplies an explicit source tree.
Compiler acceptance copies that tree to a private workspace and uses `--frozen`;
it performs no dependency acquisition. It builds the emitted multi-module fixture
on native, JS, WASM and WASM-GC and checks exact scalar results through the exported
API. A separate consumer verifies that private declarations are inaccessible.
Its JSON result records compiler, compiler bytes, core and supplied SDK tree
digests. These checks establish this generator slice; broader E2 execution parity
and provider-backed build receipts remain separate work.
