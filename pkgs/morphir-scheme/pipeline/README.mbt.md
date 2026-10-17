---
order: 40
---

# Transform scripts

The `finos/morphir-scheme/pipeline` package runs scripted IR transforms. This chapter covers a script as an
`IRFile -> IRFile` procedure, the bottom-up rewrite, the `ir-*` and JSON procedures, and the session that installs them.

Chapters: [index](../README.mbt.md) · previous: [Running Morphir IR](../backend/README.mbt.md) · next: [Specification notation](../spec/README.mbt.md)

## Scripts

`pipeline.transform_file(file, script)` expects a script that evaluates to an
`IRFile -> IRFile` procedure. For example:

```scheme
(lambda (file)
  (ir-rewrite-file file
    (lambda (node)
      (if (ir-integer? node)
          (ir-with-integer node (+ (ir-integer node) 2))
          node))))
;; => #<procedure>
```

```mbt check
///|
test "transform_file runs a script over a file" {
  let file = @frontend.compile_file("40")
  let transformed = @pipeline.transform_file(
    file, "(lambda (file) (ir-rewrite-file file (lambda (node) (if (ir-integer? node) (ir-with-integer node (+ (ir-integer node) 2)) node))))",
  )
  let entry = @ir.FQName::parse("user:main#main")
  inspect(
    @scheme.value_to_string(@backend.run_file(transformed, entry, [])),
    content="42",
  )
  inspect(
    @scheme.value_to_string(@backend.run_file(file, entry, [])),
    content="40",
  )
}
```

## Rewriting

Rewriting visits expression children before parents, including definition bodies
and application dependency implementations. Replacements are not revisited.
Attributes, patterns, types, documentation and access are retained by traversal;
`ir-with-integer` also preserves the literal's attributes. Inputs are not mutated.

```scheme
(ir-eval
  (ir-rewrite (scheme->ir "(+ 20 20)")
    (lambda (node)
      (if (ir-integer? node)
          (ir-with-integer node (+ (ir-integer node) 1))
          node))))
;; => 42
```

## Procedures

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

```scheme
(list (ir-kind (scheme->ir "42")) (ir-integer? (scheme->ir "42")) (ir-integer (scheme->ir "42")))
;; => ("Literal" #t 42)
```

```scheme
(json-write (json-read "[1, 2, null]"))
;; => "[1,2,null]"
```
