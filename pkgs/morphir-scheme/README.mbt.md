---
order: 10
---

# Morphir Scheme

An embeddable Scheme dialect for writing Morphir transforms and executing Morphir IR.
It runs on MoonBit's `wasm`, `wasm-gc`, `js` and `native` targets.
This chapter is the index and describes the core language and its embedding. The other chapters cover compiling Scheme
to Morphir IR, running Morphir IR, transform scripts and the specification notation.

Chapters: index (this page) · next: [Writing models](frontend/README.mbt.md)

| Chapter | Covers |
| --- | --- |
| [Morphir Scheme](README.mbt.md) | The language, its limits and embedding a runtime |
| [Writing models](frontend/README.mbt.md) | Compiling Scheme to Morphir IR |
| [Running Morphir IR](backend/README.mbt.md) | Evaluating and emitting IR, externals, linking, the symbols sidecar |
| [Transform scripts](pipeline/README.mbt.md) | Scripts as `IRFile -> IRFile` procedures |
| [Specification notation](spec/README.mbt.md) | Package specifications as data |

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
| `finos/morphir-scheme/spec` | The specification notation ([see the chapter](spec/README.mbt.md)) ↔ `@ir.PackageSpecification` |

[`morphir-engine`](../morphir-engine/README.md) provides file discovery, manifests,
configuration, frontend/backend registration, artifacts and diagnostics.

## Embedding

Declare `finos/morphir-scheme@0.1.0` in your module and import the needed packages.
These examples use aliases `scheme`, `frontend`, `backend`, `pipeline` and `ir`.

```mbt check
///|
test "a runtime evaluates source text" {
  let runtime = @scheme.Runtime::new()
  ignore(runtime.eval("(define (inc x) (+ x 1))"))
  let answer = runtime.eval("(inc 41)")
  inspect(@scheme.value_to_string(answer), content="42")
}
```

Sessions retain definitions. Register host procedures explicitly with
`Runtime::define_native(name, (runtime, arguments) -> Value raise)`.
Closures belong to the session that created them; calling a closure in another
session raises an error. Use `error_message(error)` to include error details.

```mbt check
///|
test "a host procedure joins the session" {
  let runtime = @scheme.Runtime::new()
  runtime.define_native("shout", fn(_runtime, arguments) raise {
    @scheme.arity(arguments, 1, "shout")
    @scheme.Text(arguments[0].as_text() + "!")
  })
  inspect(
    @scheme.value_to_string(runtime.eval("(shout \"hi\")")),
    content="\"hi!\"",
  )
}

///|
test "a closure belongs to its session" {
  let first = @scheme.Runtime::new()
  let second = @scheme.Runtime::new()
  let closure = first.eval("(lambda (x) x)")
  let message = try {
    ignore(second.call(closure, [@scheme.Unit]))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  assert_true(message != "")
}

///|
test "error_message includes the error details" {
  let runtime = @scheme.Runtime::new()
  let message = try {
    ignore(runtime.eval("(letrec ((a b) (b 1)) a)"))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="Uninitialized recursive binding: b")
}
```

Compiling Scheme to Morphir IR is described in [Writing models](frontend/README.mbt.md), running it in
[Running Morphir IR](backend/README.mbt.md), and scripted IR transforms in [Transform scripts](pipeline/README.mbt.md).

## Language

The reader supports lists and dotted pairs, quotation, vectors, strings,
characters, escaped identifiers, booleans, line comments, nested block comments
and datum comments. Numbers include arbitrary-precision decimal integers,
normalized exact rationals and finite JSON-style inexact reals.

```scheme
#| outer #| inner |# |# #; (+ 9 9) '(1 . 2)
;; => (1 . 2)
```

```scheme
(+ 18446744073709551616 1)
;; => 18446744073709551617
```

```scheme
(+ 1/3 1/6)
;; => 1/2
```

The evaluator supports lexical closures, variadic procedures, `define`, `set!`,
`lambda`, `if`, `begin`, `and`, `or`, `let`, `let*`, `letrec`, and named `let`.
It includes arithmetic, comparisons, list operations, `map`, `fold-left`, `apply`,
strings, immutable records and vectors. Only `#f` is false in the interpreter.
`letrec` rejects reads of bindings before initialization. Macro expansion,
quasiquotation, continuations, ports, mutable pairs and the full R6RS numeric
and library systems are outside this implementation.

```scheme
(define (make-adder x) (lambda (y) (+ x y)))
((make-adder 10) 32)
;; => 42
```

```scheme
((lambda (a . rest) rest) 1 2 3)
;; => (2 3)
```

```scheme
(let loop ((n 10000) (sum 0))
  (if (= n 0) sum (loop (- n 1) (+ sum 1))))
;; => 10000
```

```scheme
(list (map (lambda (x) (* x x)) '(1 2 3)) (fold-left + 0 '(1 2 3)) (apply + 1 '(2 3)))
;; => ((1 4 9) 6 6)
```

```scheme
(record-ref (record (cons "x" 42)) "x")
;; => 42
```

```scheme
(if 0 'zero-is-true 'false)
;; => zero-is-true
```

```scheme
(letrec ((a b) (b 1)) a)
;; error: Uninitialized recursive binding: b
```

## Limits

`Limits` bounds evaluation steps, recursive evaluation depth and allocated
lexical frames. Defaults are 1,000,000 steps, depth 256 and 100,000 frames.
Each public evaluation/call starts a step budget; nested host callbacks share it.
Direct tail calls use a trampoline and constant host stack, but allocate frames
in a session-owned arena. Frames are retained until the session is released;
create fresh sessions for independent jobs. Calls through `apply` and host
callbacks are depth-bounded rather than trampoline tail calls.

```mbt check
///|
test "limits bound a session and leave it usable" {
  let runtime = @scheme.Runtime::new(limits={
    steps: 100,
    depth: 32,
    frames: 100,
  })
  let message = try {
    ignore(runtime.eval("(let loop () (loop))"))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="Limit exceeded: evaluation steps")
  inspect(@scheme.value_to_string(runtime.eval("(+ 1 2)")), content="3")
  assert_eq(@scheme.Limits::default(), {
    steps: 1000000,
    depth: 256,
    frames: 100000,
  })
}
```

The language has no filesystem or network procedures. Host extensions are trusted
capabilities. These limits are execution controls, not an OS sandbox or a complete
memory/time bound: parsing, large exact arithmetic, serialization and host I/O
also consume resources. IR lowering, rewriting and pattern matching impose depth
limits. Errors propagate through the embedding API.
