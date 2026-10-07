# MoonBit Boolean source frontend

This pure package lowers explicitly typed Boolean MoonBit source to current typed
Morphir library IR. It offers two additive APIs whose semantics are checked against
the MoonBit compiler, independent truth tables and the Morphir Scheme evaluator.
The source language is `moonbit`; profiles describe the supported subset.

| API | Profile | Source contract | Entry contract |
| --- | --- | --- | --- |
| `compile` | `moonbit-model-bool-v1` | One function; Boolean expressions | One `entry`, with `public` visibility |
| `compile_library` | `moonbit-model-bool-library-v1` | Several functions; direct calls and immutable lets | Sorted public `entries`; all-private libraries have none |

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

The original `compile` contract remains:

- Exactly one ordinary top-level function, with default or plain `pub`
  visibility. Every positional named parameter and the return type must explicitly
  use unqualified `Bool`. Zero parameters are allowed.
- Explicit `priv fn` is rejected, matching the pinned compiler. Plain `fn` is
  unexported; `pub fn` is exported.
- Boolean literals, parameter references, grouping, explicit `Bool` constraints,
  `if` with `else`, `!`, `&&`, `||`, `==` and `!=`.
- Comments and whitespace accepted by the pinned parser.

Imports, calls, recursion, local bindings, mutation, loops, early returns, methods,
generics, attributes, effects, async functions, other types and recovered syntax
are rejected. Equality binds operands once in source order. Boolean conjunction
and disjunction lower to short-circuit conditionals. Every lowered value has a
Boolean type attribute. Source names use an injective UTF-8 hex encoding, with a
separate namespace for generated temporary bindings.

## Boolean libraries

`compile_library` accepts the same `Input` and returns `LibraryOutput`: typed IR,
the canonical public entry list, native Ion metadata, annotations and provenance.
It checks every function, including unused private helpers. Signatures are collected
before bodies, so forward references work.

```moonbit
pub fn eligible(active : Bool, vip : Bool, suspended : Bool) -> Bool {
  let allowed : Bool = ready(active, vip)
  allowed && !suspended
}

pub fn default_ready() -> Bool { ready(true, false) }

fn ready(active : Bool, vip : Bool) -> Bool { active || vip }
```

Beyond the original expression forms, this profile supports direct, unqualified,
fully applied within-file calls, including zero-argument calls, and sequential
single-name immutable `let` bindings with optional `Bool` annotations. An initializer
sees the preceding scope; each shadowed binding receives a distinct identity. A
Boolean binding shadowing a function name cannot be called. All call arguments,
binding values and function results must be Boolean.

Function values, partial applications, labelled or optional arguments, destructuring,
local functions and discarded expression statements are rejected. Imports, other
types, effects and the remaining exclusions above also remain unsupported. Direct
and indirect recursion are rejected across the whole unit, including calls in
constant-false branches. Calls remain references in IR; lowering never inlines or
expands the call graph. Equality binds operands once, lets are eager, and Boolean
conjunction/disjunction retain their short-circuit boundaries.

This pure API compiles a library without host access. The
[engine adapter](../morphir-engine/moonbit/README.md) offers both profiles under
language `moonbit`, preserving the seed default. Select the library with
`frontend.profile = "moonbit-model-bool-library-v1"` or CLI
`--frontend-profile moonbit-model-bool-library-v1`. Provider identity and configured
source capabilities belong to the engine descriptor. Full installed library parity
qualification and A2 extension packaging remain separate roadmap work.


## Diagnostics and bounds

Validation raises `FrontendError::Invalid` with a stable
`moonbit_frontend.<code>` diagnostic, detail and a source span when available.
Default hard caps are 65,536 UTF-8 source bytes, 16 parameters, expression depth
64 and 4,096 visited source expressions. Callers can lower these limits. `Limits::validate()` and
`LibraryLimits::validate()` check budgets without parsing source, allowing adapters
to validate capability claims before registration.
Cancellation runs before and after parsing and at every lowering visit.

`LibraryLimits` additionally bounds the entire library:

| Budget | Hard default | Scope |
| --- | ---: | --- |
| UTF-8 source bytes | 65,536 | Unit |
| Functions | 64 | Unit |
| Positional parameters | 16 | Function |
| Immutable lets | 256 | Function |
| Visited source expressions | 4,096 | Unit, including call identifiers |
| Call sites | 1,024 | Unit |
| Expression depth | 64 | Root at depth zero |
| Call graph depth | 32 | Edges on the longest path |

Callers can tighten these budgets, including zero parameters, lets, calls or depth,
but cannot increase them. Validation returns one primary diagnostic and no partial
library. Diagnostic order follows fixed phases: input, parse, signatures and syntax
adaptation, lexical resolution, body/call-graph checks, then lowering. Each body pass
uses declaration order and source expression order. Cancellation is polled between
phases and during bounded walks. Acyclic calls can still produce expensive runtime
evaluation; admission budgets are not an execution deadline.

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

Library provenance separates `language: "moonbit"` from `profile`; the original
profile's provenance shape stays unchanged. Library body metadata retains nested
binding and call origins beneath its stable body node ID, including both source
spelling and unique binding identity. Intermediate `Reference` and `Apply` values
carry the appropriate curried function types; final results carry `Bool`.

## Observations

`compile(scope=observer.scope())` accepts an optional portable observation scope.
The default is disabled and performs no clock, ID or sink work. A `frontend` span
contains `parse`, declaration/signature `profile-check`, and expression checking
`lower` spans. The latter intentionally combines body typing and IR lowering.
Cancellation ends active spans as cancelled and preserves the original frontend
diagnostic. Required diagnostics stay outside the observation channel. Typed sink
failures leave IR, source origins and provenance unchanged.

The host supplies clocks, IDs and delivery. Default records contain no source,
logical unit IDs, paths, names or diagnostic text. This package imports the portable
`finos/morphir-execution/observability` contract and no logging backend or host API.

`compile_library` has ordered children `parse`, `profile-check` (signatures and
syntax), `resolve`, `profile-check` (bodies and whole graph), and `lower`. The two
profile-check occurrences are distinguished by their fixed position around
resolution. It uses the same disabled default, sink containment and privacy rules;
the original API's stage sequence is unchanged.

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

The gate covers 11 original-profile models and six libraries with 13 public entries:
86 Boolean rows per target/mode. It also checks that every private fixture symbol
is inaccessible to a separate consumer in both original and generated libraries,
and that the pinned compiler rejects explicit `priv fn` (diagnostic 3005). The
all-private library builds without an inferred entry. Pure tests exercise rejection,
exact/tightened budgets, graph depth, Ion origins and observation behavior.

Receipts default to `.dev/frontend-acceptance/`; set `MORPHIR_FRONTEND_RECEIPTS` to
choose another directory. They retain model sources, typed JSON IR, generated
sources, binary Ion symbol files, lane logs and source/dependency/toolchain
identities. `MORPHIR_FRONTEND_SDK` can supply an explicit SDK source directory.
