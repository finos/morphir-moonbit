---
order: 20
---

# Writing models

The `finos/morphir-scheme/frontend` package lowers Scheme expressions and files to current Morphir IR.
This chapter covers `compile_expression` and `compile_file` with its options, the functional subset the frontend
accepts and rejects, and the type placeholders that `fill` solves.

Chapters: [index](../README.mbt.md) · previous: [Morphir Scheme](../README.mbt.md) · next: [Running Morphir IR](../backend/README.mbt.md)

## Compile an expression or a file

Declare `finos/morphir-scheme@0.1.0` in your module and import `finos/morphir-scheme/frontend`. The examples use the
aliases `scheme`, `frontend`, `backend` and `ir`. Running the compiled IR is described in
[Running Morphir IR](../backend/README.mbt.md).

```mbt check
///|
test "compile an expression and a file" {
  let value = @frontend.compile_expression("(let ((x 6)) (* x 7))")
  let result = @backend.evaluate(value)
  inspect(@scheme.value_to_string(result), content="42")
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let answer = @backend.run_file(file, @ir.FQName::parse("user:main#main"), [])
  inspect(@scheme.value_to_string(answer), content="42")
}
```

`compile_file` accepts `package_name` and `module_name`. Leading definitions
become module values; remaining expressions become `main`.

```mbt check
///|
test "compile_file names the package and module" {
  let file = @frontend.compile_file(
    "(define (inc x) (+ x 1)) (inc 41)",
    package_name="my/pkg",
    module_name="util",
  )
  let answer = @backend.run_file(file, @ir.FQName::parse("my/pkg:util#main"), [])
  inspect(@scheme.value_to_string(answer), content="42")
}
```

In the Scheme examples of this chapter, each block is compiled as a file in module `main` and its `main` is run.
A block that starts with `;; file: <path>` is one file of a project, and the last block of the project states the
result.

```scheme
(define (inc x) (+ x 1))
(inc 41)
;; => 42
```

## The functional subset

The frontend accepts the functional subset: literals, literal lists, identifiers,
curried lambdas and calls, boolean `if`, `begin`, `let`/`let*`/`letrec`, lists,
arithmetic, binary comparisons, and leading file definitions.

```scheme
(define (fact n)
  (if (= n 0) 1 (* n (fact (- n 1)))))
(let* ((a 4) (b (+ a 1)))
  (list (fact b) (+ 1 2 3)))
;; => (120 6)
```

It rejects mutation,
zero-argument lambdas/calls, named `let`, rational literals, vectors and quoted
symbols.

```scheme
(let ((x 1)) (set! x 2) x)
;; error: Unsupported: Cannot lower set! to functional Morphir IR
```

```scheme
(lambda () 1)
;; error: Unsupported: Morphir lambdas require a parameter; use unit explicitly
```

```scheme
(let loop ((n 3)) n)
;; error: Expected proper syntax list
```

The message for a named `let` is a placeholder; bead `morphir-ukvn.5.46` tracks a clear error for it.

```scheme
(+ 1/2 1/2)
;; error: Unsupported: Exact rational literals have no direct Morphir literal
```

```scheme
(quote (a b))
;; error: Unsupported: Quoted symbols, vectors and improper lists cannot be lowered to Morphir literals
```

Local names use Morphir's canonical naming rules; qualified names can
refer to other modules.

```mbt check
///|
test "a qualified name refers to another module" {
  let value = @frontend.compile_expression("(user:util#inc 41)")
  let text = @backend.emit_expression(value)
  assert_true(text.contains("r:user:util#inc"))
}
```

IR conditions must be boolean, so programs relying on Scheme truthiness are
outside the portable frontend subset.

```scheme
(if 0 1 2)
;; error: Unsupported: Morphir conditions must be boolean
```

First-class primitives use Morphir's
curried SDK signatures; variadic arithmetic is lowered at direct call sites.

## Type placeholders and `fill`

Signatures use `t-<n>` type variables with the unknown marker
(`morphir.inference = unknown`), one for each position, and integer literals carry the type `Int`. With
`pipeline.inference = "fill"`, the engine solves them. This is structural lowering, not type inference or type checking.

`fill` has two limits on Scheme input. A call from one top-level `define` to another, or a top-level `define`
that calls itself, fails with `unknown_reference`, because the frontend lowers that reference as a local variable; bead
`morphir-ukvn.5.22.8` tracks the fix. Integer literals always have the type `Int`, so Float arithmetic must use a
decimal literal: write `(* 2.5 2.0)`, because `(* 2.5 2)` fails with `type_mismatch` (expected `Float`, found
`Int`).

```scheme
(* 2.5 2.0)
;; => 5.0
```
