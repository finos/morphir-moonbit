# MoonBit Boolean source frontend

This package lowers one explicitly typed MoonBit function to current typed Morphir
library IR. The `moonbit-model-bool-v1` profile is deliberately small so its
semantics can be checked against the MoonBit compiler and the Morphir Scheme
evaluator before extending it.

```moonbit
pub fn eligible(active : Bool, vip : Bool) -> Bool {
  active && !vip
}
```

Call `compile` with an `Input` containing a logical `unit_id`, canonical Morphir
`package_name` and `module_name`, and source text. Its `Output` contains typed IR,
the function entry, visibility, native Ion metadata, annotations and provenance.
The package performs no file, process, registry or engine operations. The separate
[engine adapter](../morphir-engine/moonbit/README.md) maps this output to an `IRUnit`
and the Morphir CLI registers it explicitly. A2 extension packaging remains
separate work.

## Supported source

- Exactly one ordinary top-level function, with default, `priv` or plain `pub`
  visibility. Every positional named parameter and the return type must explicitly
  use unqualified `Bool`. Zero parameters are allowed.
- Boolean literals, parameter references, grouping, explicit `Bool` constraints,
  `if` with `else`, `!`, `&&`, `||`, `==` and `!=`.
- Comments and whitespace accepted by the pinned parser.

Imports, calls, recursion, local bindings, mutation, loops, early returns, methods,
generics, attributes, effects, async functions, other types and recovered syntax
are rejected. Equality binds operands once in source order. Boolean conjunction
and disjunction lower to short-circuit conditionals. Every lowered value has a
Boolean type attribute. Source names use an injective UTF-8 hex encoding, with a
separate namespace for generated temporary bindings.

## Diagnostics and bounds

Validation raises `FrontendError::Invalid` with a stable
`moonbit_frontend.<code>` diagnostic, detail and a source span when available.
Default hard caps are 65,536 UTF-8 source bytes, 16 parameters, expression depth
64 and 4,096 visited source expressions. Callers can lower these limits.
Cancellation runs before and after parsing and at every lowering visit.

These are admission and lowering limits. The parser is synchronous and does not
offer a cancellation callback or a hard internal allocation budget. Hosts that
accept untrusted source need their own execution isolation and deadline.

Spans retain parser positions under `moonbit-parser-position-v1`: lines are
one-based and columns are zero-based `cnum - bol` in the parser's native units.
Consumers must not assume those columns are UTF-8 byte offsets. Declaration,
parameter and body origins retain source spelling in native Ion values.
Provenance records the profile, parser version and logical unit identity. Host
receipts supply source and toolchain digests; the pure frontend does not claim a
filesystem identity.

## Pins and acceptance

The parser is `moonbitlang/parser@0.4.1`, lexer `moonbitlang/lexer@0.4.0`, and Ion
is `moonrockz/ion@0.3.0`. Ion remains the preferred engine representation. Current
Morphir JSON serialization remains supported and is checked in frontend tests.

Run focused tests with:

```sh
moon test -p finos/morphir-moonbit-frontend --target all
```

`MOON_HOME=/path/to/pinned/moon mise run test:moonbit-frontend` builds the original
source and generated libraries in a private workspace using supplied SDK source,
then compares their Boolean truth tables with independent expectations and Scheme
results on JS, native, Wasm and Wasm GC, in debug and release modes. It uses compiler
and core `0.10.14+7d59c7ec9` and the SDK's pinned semantic bindings. It performs no
registry acquisition in the external workspace. The acceptance executable is a
test fixture, not an engine integration API.

Receipts default to `.dev/frontend-acceptance/`; set `MORPHIR_FRONTEND_RECEIPTS` to
choose another directory. They retain model sources, typed JSON IR, generated
sources, binary Ion symbol files, lane logs and source/dependency/toolchain
identities. `MORPHIR_FRONTEND_SDK` can supply an explicit SDK source directory.
