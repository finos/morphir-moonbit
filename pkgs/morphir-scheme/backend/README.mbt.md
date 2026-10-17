---
order: 30
---

# Running Morphir IR

The `finos/morphir-scheme/backend` package turns Morphir IR into executable Scheme and runs it. This chapter covers
`evaluate`, `run_file` and the emitters, the SDK bridge, externals, natives and accelerators, linking, and the units
that carry a symbols sidecar and source comments.

Chapters: [index](../README.mbt.md) · previous: [Writing models](../frontend/README.mbt.md) · next: [Transform scripts](../pipeline/README.mbt.md)

## Evaluate, run and emit

The examples use the aliases `scheme`, `frontend`, `backend` and `ir`. The IR in them comes from the frontend, which is
described in [Writing models](../frontend/README.mbt.md).

```mbt check
///|
test "evaluate an expression and run a file" {
  let value = @frontend.compile_expression("(let ((x 6)) (* x 7))")
  let result = @backend.evaluate(value)
  inspect(@scheme.value_to_string(result), content="42")
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let answer = @backend.run_file(file, @ir.FQName::parse("user:main#main"), [])
  inspect(@scheme.value_to_string(answer), content="42")
}
```

`emit_expression`
and `emit_file` return Scheme text. Install backend support with `backend.install`
before evaluating emitted text, then use `call_entry` for a qualified entry point.

```mbt check
///|
test "emit Scheme text, install support, call an entry point" {
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let text = @backend.emit_file(file)
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(text))
  let answer = @backend.call_entry(
    runtime,
    @ir.FQName::parse("user:main#main"),
    [],
  )
  inspect(@scheme.value_to_string(answer), content="42")
}
```

`backend.evaluate` calls a registered SDK or host accelerator directly when a
reference has all its arguments. `backend.evaluate_in(runtime, value)` and
`backend.run_file_in(runtime, file, entry, arguments)` accept a caller-owned
runtime so an embedding host can install bindings first. Other expressions use
the Scheme evaluator. Native callbacks and Scheme callbacks share one step and
cancellation budget per evaluation.

```mbt check
///|
test "a caller-owned runtime keeps its bindings" {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let value = @frontend.compile_expression("(+ 40 2)")
  inspect(
    @scheme.value_to_string(@backend.evaluate_in(runtime, value)),
    content="42",
  )
}
```

## The backend and its boundary

The backend supports IR literals, functions, records, tuples, lists, constructors,
patterns, recursion, and Library/Application distributions. Tuples use vectors,
constructors use tagged values, and decimal/document literals retain their data
as tagged values. Top-level definitions are resolved through thunks; pure constants
are recomputed when referenced. Libraries supply dependency specifications only;
install required implementations in the same runtime. Applications include their
dependency implementations. This backend ships a small SDK bridge for arithmetic,
comparison, strings, list operations, Maybe and Result, not the entire Morphir SDK.

```scheme
(list (+ 1 2) (string-append "ab" "c") (%morphir-tag "morphir/SDK:maybe#just" 1))
;; => (3 "abc" #<morphir/SDK:maybe#just 1>)
```

### Externals, natives and accelerators

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

```mbt check
///|
fn doc_file(definition : @ir.ValueDefinition) -> @ir.IRFile raise {
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map::from_array([
    (
      @ir.Name::parse("main"),
      { access: @ir.Access::Public, value: { doc: None, value: definition, }, },
    ),
  ])
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("test"), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("main"),
          {
            access: @ir.Access::Public,
            value: { types: Map([]), values, doc: None, },
          },
        ),
      ]),
    }),
  )
}

///|
test "an external body uses a registered binding, else its fallback" {
  let entry = @ir.FQName::parse("test:main#main")
  let fallback = @ir.Value::Literal(
    @ir.ValueAttributes::default(),
    @ir.Literal::IntegerLiteral("44"),
  )
  let definition = @ir.ValueDefinition::ExternalBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    [{ target_platform: "morphir-scheme", external_name: "answer", }],
    Some(fallback),
  )
  let portable = @backend.run_file(doc_file(definition), entry, [])
  inspect(@scheme.value_to_string(portable), content="44")
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_external(runtime, "answer", 0, fn(
    _runtime,
    _arguments,
  ) raise {
    @scheme.integer("42")
  })
  let hosted = @backend.run_file_in(runtime, doc_file(definition), entry, [])
  inspect(@scheme.value_to_string(hosted), content="42")
  let duplicate = try {
    @backend.register_external(runtime, "answer", 0, fn(
      _runtime,
      _arguments,
    ) raise {
      @scheme.integer("1")
    })
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  assert_true(duplicate != "")
  @backend.replace_external(runtime, "answer", 0, fn(
    _runtime,
    _arguments,
  ) raise {
    @scheme.integer("43")
  })
  let replaced = @backend.run_file_in(runtime, doc_file(definition), entry, [])
  inspect(@scheme.value_to_string(replaced), content="43")
}
```

### Linking

`backend.link_file` checks required bindings and registered arities before
execution. Local native bodies have no binding identity and are rejected.
Scheme text values still use MoonBit `String`; SDK `Text` results containing an
isolated surrogate require a separate runtime value representation before they
can cross this boundary.
Holes, incomplete definitions and Specs distributions cannot execute.

```mbt check
///|
test "linking rejects a mismatched accelerator arity" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::ExpressionBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    @ir.Value::Literal(
      @ir.ValueAttributes::default(),
      @ir.Literal::IntegerLiteral("44"),
    ),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_accelerator(runtime, entry, 1, fn(
    _runtime,
    _arguments,
  ) raise {
    @scheme.integer("42")
  })
  let message = try {
    @backend.link_file(runtime, doc_file(definition))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  assert_true(message.contains("arity mismatch"))
}
```

## Units, sidecar and source comments

`backend.emit_unit(unit, source_path?)` generates from a rich unit: a `backend.Input` with the unit id, the
`IRFile`, node metadata (`node_id`, Ion `data`), ordered annotation tokens and provenance, the contract that the
MoonBit generator's `Input` also follows. It returns a `backend.Output`: the Scheme `source` text and the binary Ion
`symbols` sidecar. `emit_unit(Input::new(id, ir)).source` equals `emit_file(ir)`; `emit_file` never writes
comments or a sidecar. The engine writes the two as `<unit>.scm` and `<unit>.symbols.10n` (format `ion-binary`)
for every rich frontend, and only `<unit>.scm` for the plain `scheme` and `ir-json` frontends. The backend always
returns a sidecar, even for a unit with no metadata, so that a consumer can rely on it.

```mbt check
///|
test "emit_unit returns the emit_file text and a sidecar" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let output = @backend.emit_unit(@backend.Input::new("Main", ir))
  assert_eq(output.source, @backend.emit_file(ir))
  assert_true(output.symbols.length() > 0)
}
```

The sidecar is one record annotated `morphir_scheme_symbols`, profile `morphir-scheme-symbols-v1`, naming policy
`scheme-canonical-identity-v1`: Scheme binds each value to its canonical Morphir name, so the generated name of
every symbol is its fqname. Fields, in order: `profile`, `naming_policy`, `unit_id`, `source_annotations`,
`source_provenance` (unchanged), `source_nodes` (the owned node ids), `metadata` (every entry, unchanged, in the
unit's order) and `symbols`. A symbol has `fqname`, `generated_name` (the same), `scheme_symbol` (the `r:` symbol
as written), `public` (value and module both public), `source_node` (`value:<fqname>`), `generated_node`
(`scheme:define:<fqname>`) and `origins` (`source_node` and `source_node/body`, each only when the unit owns it, so
a native or external value lists no body and an application's declarations list none). Unlike `morphir-moonbit-symbols-v1` it has no `warnings`,
`naming_allocations`, `consumed_naming_facts`, `unvalidated_predicates` or `source_ir_json`: Scheme recovers no
names and the checkpoint backend carries IR. Metadata is copied without ownership validation; the engine validates
rich units when a frontend returns them. The bytes are a pure function of the unit.

```mbt check
///|
test "the sidecar names its profile and its symbols" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let output = @backend.emit_unit(@backend.Input::new("Main", ir))
  let stored = @ion_binary.read_binary_value(output.symbols[:])
  assert_eq(stored.annotations().map(a => a.text()), [
    Some("morphir_scheme_symbols"),
  ])
  guard stored.kind() is @ion.Struct(fields) else { fail("Expected a record") }
  assert_eq(fields.map(field => field.name().text().unwrap()), [
    "profile", "naming_policy", "unit_id", "source_annotations", "source_provenance",
    "source_nodes", "metadata", "symbols",
  ])
  assert_eq(@backend.SYMBOLS_PROFILE, "morphir-scheme-symbols-v1")
}
```

Above each `define` whose unit metadata entry `value:<fqname>` has a `declaration` record with a `name`, the text
carries `;; <name> (<path>:<line>:<column>)`. The path is the record's `path` field, else `source_path`, else
the unit id; the position is `start_line:start_column` when the four coordinates are non-negative integers with
the end not before the start, else the comment is `;; <name> (<path>)`. A field that occurs more than once, an
entry that occurs more than once, a name or path that is empty, longer than 256 characters, or holds a control
character or a line or paragraph separator, is ignored: no hint can end the comment early. Comments change no name
and no behaviour.

```mbt check
///|
test "a declaration record becomes a source comment" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let declaration = @ion.IonValue::new(
    @ion.Struct([
      @ion.Field::new("name", @ion.IonValue::string("inc")),
      @ion.Field::new("path", @ion.IonValue::string("src/Main.elm")),
      @ion.Field::new("start_line", @ion.IonValue::int(3)),
      @ion.Field::new("start_column", @ion.IonValue::int(1)),
      @ion.Field::new("end_line", @ion.IonValue::int(3)),
      @ion.Field::new("end_column", @ion.IonValue::int(20)),
    ]),
  )
  let metadata = @ion.IonValue::new(
    @ion.Struct([@ion.Field::new("declaration", declaration)]),
  )
  let input = {
    ..@backend.Input::new("Main", ir),
    metadata: [{ node_id: "value:user:main#inc", data: metadata, }],
  }
  let output = @backend.emit_unit(input)
  assert_true(output.source.contains(";; inc (src/Main.elm:3:1)\n"))
  assert_true(@backend.emit_file(ir) != output.source)
}
```
