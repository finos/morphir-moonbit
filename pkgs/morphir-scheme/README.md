# Morphir Scheme

An embeddable Scheme dialect for writing Morphir transforms and executing Morphir IR.
It runs on MoonBit's `wasm`, `wasm-gc`, `js` and `native` targets.

The separation of reader, evaluator and runtime takes inspiration from
[bobzhang/scheme-r6rs](https://mooncakes.io/docs/bobzhang/scheme-r6rs) and its
[MoonBit implementation](https://github.com/bobzhang/moonbit-scheme-r6rs).
This is an independent implementation of a specialized subset, not an R6RS implementation.

## Packages

| Import | Responsibility |
| --- | --- |
| `finos/morphir-scheme` | Reader, runtime values, lexical evaluation and host procedures |
| `finos/morphir-scheme/frontend` | Scheme expressions and files → current Morphir IR |
| `finos/morphir-scheme/backend` | Morphir IR → executable Scheme; runtime support |
| `finos/morphir-scheme/pipeline` | Scripted IR transforms, JSON bridge and bottom-up traversal |

[`morphir-engine`](../morphir-engine/README.md) provides file discovery, manifests,
configuration, frontend/backend registration, artifacts and diagnostics.

## Embedding

Declare `finos/morphir-scheme@0.1.0` in your module and import the needed packages.
These examples use aliases `scheme`, `frontend`, `backend`, `pipeline` and `ir`.

```moonbit
let runtime = @scheme.Runtime::new()
ignore(runtime.eval("(define (inc x) (+ x 1))"))
let answer = runtime.eval("(inc 41)")
println(@scheme.value_to_string(answer)) // 42
```

Sessions retain definitions. Register host procedures explicitly with
`Runtime::define_native(name, (runtime, arguments) -> Value raise)`.
Closures belong to the session that created them; calling a closure in another
session raises an error. Use `error_message(error)` to include error details.

```moonbit
let value = @frontend.compile_expression("(let ((x 6)) (* x 7))")
let result = @backend.evaluate(value)
let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
let answer = @backend.run_file(file, @ir.FQName::parse("user:main#main"), [])
```

`compile_file` accepts `package_name` and `module_name`. Leading definitions
become module values; remaining expressions become `main`. `emit_expression`
and `emit_file` return Scheme text. Install backend support with `backend.install`
before evaluating emitted text, then use `call_entry` for a qualified entry point.

`backend.evaluate` calls a registered SDK or host accelerator directly when a
reference has all its arguments. `backend.evaluate_in(runtime, value)` and
`backend.run_file_in(runtime, file, entry, arguments)` accept a caller-owned
runtime so an embedding host can install bindings first. Other expressions use
the Scheme evaluator. Native callbacks and Scheme callbacks share one step and
cancellation budget per evaluation.

## Transform scripts

`pipeline.transform_file(file, script)` expects a script that evaluates to an
`IRFile -> IRFile` procedure. For example:

```scheme
(lambda (file)
  (ir-rewrite-file file
    (lambda (node)
      (if (ir-integer? node)
          (ir-with-integer node (+ (ir-integer node) 2))
          node))))
```

Rewriting visits expression children before parents, including definition bodies
and application dependency implementations. Replacements are not revisited.
Attributes, patterns, types, documentation and access are retained by traversal;
`ir-with-integer` also preserves the literal's attributes. Inputs are not mutated.

| Procedure | Operation |
| --- | --- |
| `ir-read`, `ir-write` | Read a versioned IR JSON file into current IR; write current JSON |
| `ir-value-read`, `ir-value-write` | Read/write a current IR expression |
| `ir->datum`, `datum->ir` | Convert an expression to/from the current JSON model as Scheme data |
| `json-read`, `json-write` | JSON objects as records, arrays as lists, null as unit |
| `scheme->ir`, `ir->scheme`, `ir-eval` | Compile, emit or execute one expression |
| `ir-kind` | Current expression constructor name |
| `ir-integer?`, `ir-integer`, `ir-with-integer` | Inspect and replace exact integer literals |
| `ir-rewrite`, `ir-rewrite-file` | Bottom-up typed transformation |

`pipeline.new_runtime()` installs these procedures in a persistent session.
`ir-read` uses the existing versioned codecs and migrations, including canonical
Elm encodings for v1–v3. The unversioned model follows the latest supported IR.

## Language and execution boundary

The reader supports lists and dotted pairs, quotation, vectors, strings,
characters, escaped identifiers, booleans, line comments, nested block comments
and datum comments. Numbers include arbitrary-precision decimal integers,
normalized exact rationals and finite JSON-style inexact reals.

The evaluator supports lexical closures, variadic procedures, `define`, `set!`,
`lambda`, `if`, `begin`, `and`, `or`, `let`, `let*`, `letrec`, and named `let`.
It includes arithmetic, comparisons, list operations, `map`, `fold-left`, `apply`,
strings, immutable records and vectors. Only `#f` is false in the interpreter.
`letrec` rejects reads of bindings before initialization. Macro expansion,
quasiquotation, continuations, ports, mutable pairs and the full R6RS numeric
and library systems are outside this implementation.

The frontend accepts the functional subset: literals, literal lists, identifiers,
curried lambdas and calls, boolean `if`, `begin`, `let`/`let*`/`letrec`, lists,
arithmetic, binary comparisons, and leading file definitions. It rejects mutation,
zero-argument lambdas/calls, named `let`, rational literals, vectors and quoted
symbols. Local names use Morphir's canonical naming rules; qualified names can
refer to other modules. Signatures use `scheme-value` type variables where types
are unknown. This is structural lowering, not type inference or type checking.
IR conditions must be boolean, so programs relying on Scheme truthiness are
outside the portable frontend subset. First-class primitives use Morphir's
curried SDK signatures; variadic arithmetic is lowered at direct call sites.

The backend supports IR literals, functions, records, tuples, lists, constructors,
patterns, recursion, and Library/Application distributions. Tuples use vectors,
constructors use tagged values, and decimal/document literals retain their data
as tagged values. Top-level definitions are resolved through thunks; pure constants
are recomputed when referenced. Libraries supply dependency specifications only;
install required implementations in the same runtime. Applications include their
dependency implementations. This backend ships a small SDK bridge for arithmetic,
comparison, strings, list operations, Maybe and Result, not the entire Morphir SDK.

External bodies try registered `morphir-runtime`, `morphir-scheme`, or `scheme`
bindings in declaration order. If none is registered, they evaluate the portable
fallback. Errors from an invoked binding propagate without retrying the
fallback. Hosts use `backend.register_external(runtime, name, arity, procedure)`
for external bindings, `backend.register_native(runtime, fqname, procedure)`
for top-level native bodies, and `backend.register_accelerator(runtime, fqname,
arity, procedure)` to accelerate an expression body. Duplicate registrations
fail; `replace_native`, `replace_external`, and `replace_accelerator` are
explicit overrides. Native body callbacks receive the arguments declared by
the IR signature when invoked through `run_file_in`.
`backend.link_file` checks required bindings and registered arities before
execution. Local native bodies have no binding identity and are rejected.
Scheme text values still use MoonBit `String`; SDK `Text` results containing an
isolated surrogate require a separate runtime value representation before they
can cross this boundary.
Holes, incomplete definitions and Specs distributions cannot execute.

## Limits

`Limits` bounds evaluation steps, recursive evaluation depth and allocated
lexical frames. Defaults are 1,000,000 steps, depth 256 and 100,000 frames.
Each public evaluation/call starts a step budget; nested host callbacks share it.
Direct tail calls use a trampoline and constant host stack, but allocate frames
in a session-owned arena. Frames are retained until the session is released;
create fresh sessions for independent jobs. Calls through `apply` and host
callbacks are depth-bounded rather than trampoline tail calls.

The language has no filesystem or network procedures. Host extensions are trusted
capabilities. These limits are execution controls, not an OS sandbox or a complete
memory/time bound: parsing, large exact arithmetic, serialization and host I/O
also consume resources. IR lowering, rewriting and pattern matching impose depth
limits. Errors propagate through the embedding API.
