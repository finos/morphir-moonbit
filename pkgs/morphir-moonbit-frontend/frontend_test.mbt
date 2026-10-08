///|
fn input(source : String) -> @frontend.Input {
  { unit_id: "model.mbt", package_name: "model", module_name: "main", source, }
}

///|
fn definition(body : String) -> String {
  "pub fn decide(active : Bool, vip : Bool) -> Bool { " + body + " }"
}

///|
fn failure(source : String) -> @frontend.Diagnostic raise {
  try {
    ignore(@frontend.compile(input(source)))
    fail("Expected frontend failure")
  } catch {
    @frontend.Invalid(diagnostic) => diagnostic
    error => raise error
  }
}

///|
fn result(output : @frontend.Output, active : Bool, vip : Bool) -> Bool raise {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(@backend.emit_file(output.ir)))
  match
    @backend.call_entry(runtime, output.entry, [
      @scheme.Boolean(active),
      @scheme.Boolean(vip),
    ]) {
    Boolean(value) => value
    _ => {
      fail("Expected Boolean outcome")
      false
    }
  }
}

///|
test "Boolean operators and conditionals match independent truth tables" {
  let cases = [
    ("active && vip", [false, false, false, true]),
    ("active || vip", [false, true, true, true]),
    ("active == vip", [true, false, false, true]),
    ("active != vip", [false, true, true, false]),
    ("!active", [true, true, false, false]),
    ("if active { vip } else { !vip }", [true, false, false, true]),
    ("((active && !vip) || (!active && vip))", [false, true, true, false]),
    ("(active == vip) != (!active == !vip)", [false, false, false, false]),
    ("(active : Bool)", [false, false, true, true]),
    ("true", [true, true, true, true]),
    ("false", [false, false, false, false]),
  ]
  for (body, expected) in cases {
    let output = @frontend.compile(input(definition(body)))
    assert_true(output.public)
    assert_eq(@ir_json.read(@ir_json.write(output.ir)), output.ir)
    let values = [
      result(output, false, false),
      result(output, false, true),
      result(output, true, false),
      result(output, true, true),
    ]
    assert_eq(values, expected, msg=body)
  }
}

///|
test "source operators lower to conditional short circuit boundaries" {
  for operator in ["&&", "||"] {
    let output = @frontend.compile(
      input(definition("active " + operator + " vip")),
    )
    guard output.ir.distribution is Library(_, _, package_def) else {
      fail("Expected library")
    }
    let module_def = package_def.modules.values().collect()[0].value
    guard module_def.values.values().collect()[0].value.value
      is ExpressionBody(_, _, IfThenElse(_, _, _, _)) else {
      fail("Short circuit must be represented by a conditional")
    }
  }
}

///|
test "Boolean equality does not duplicate operand trees" {
  let output = @frontend.compile(input(definition("active == vip")))
  guard output.ir.distribution is Library(_, _, package_def) else {
    fail("Expected library")
  }
  let module_def = package_def.modules.values().collect()[0].value
  guard module_def.values.values().collect()[0].value.value
    is ExpressionBody(
      _,
      _,
      LetDefinition(_, left, _, LetDefinition(_, right, _, _))
    ) else {
    fail("Equality must bind both operands in order")
  }
  assert_true(left != right)
}

///|
test "unsupported and invalid syntax never returns a partial model" {
  let cases = [
    (definition("42"), "unsupported_expression"),
    (definition("missing"), "unknown_reference"),
    (definition("active + vip"), "unsupported_operator"),
    (definition("let mut x = active; x = vip; x"), "unsupported_expression"),
    (definition("decide(active, vip)"), "unsupported_expression"),
    (definition("@other.ready"), "qualified_reference"),
    (definition("if active { vip }"), "unsupported_expression"),
    (definition("return active"), "unsupported_expression"),
    (definition("(active, vip)"), "unsupported_expression"),
    (definition("todo()"), "unsupported_expression"),
    ("pub fn bad(x : Int) -> Bool { true }", "unsupported_type"),
    ("pub fn bad(x : Bool) { x }", "unsupported_type"),
    ("pub fn bad(x) -> Bool { x }", "unsupported_type"),
    ("pub fn bad(x : Bool, x : Bool) -> Bool { x }", "duplicate_parameter"),
    ("pub fn bad(x~ : Bool) -> Bool { x }", "unsupported_parameters"),
    ("pub fn[T] bad(x : Bool) -> Bool { x }", "unsupported_function"),
    ("pub async fn bad(x : Bool) -> Bool { x }", "unsupported_function"),
    ("pub fn bad(x : Bool) -> Bool raise { x }", "unsupported_function"),
    ("priv fn bad(x : Bool) -> Bool { x }", "unsupported_visibility"),
    ("let enabled = true", "unsupported_declaration"),
    ("test { assert_true(true) }", "unsupported_declaration"),
    (definition("active") + "\n" + definition("vip"), "declaration_count"),
    (definition("if }"), "syntax"),
  ]
  for (source, code) in cases {
    let actual = failure(source).code
    assert_eq(actual, "moonbit_frontend." + code, msg=source + ": " + actual)
  }
}

///|
test "parser recovery diagnostics retain source coordinates" {
  let diagnostic = failure("\n\npub fn bad(x : Bool) -> Bool { if }")
  assert_eq(diagnostic.code, "moonbit_frontend.syntax")
  assert_true(diagnostic.source.unwrap().start_line >= 3)
}

///|
test "qualified Boolean annotations are unsupported at every type boundary" {
  for
    source in [
      "pub fn bad(x : @other.Bool) -> Bool { true }", "pub fn bad(x : Bool) -> @other.Bool { x }",
      "pub fn bad(x : Bool) -> Bool { (x : @other.Bool) }",
    ] {
    assert_eq(failure(source).code, "moonbit_frontend.unsupported_type")
  }
}

///|
test "encoded source names preserve spelling distinctions" {
  let first = @frontend.compile(input("pub fn is_ready() -> Bool { true }"))
  let second = @frontend.compile(input("pub fn isReady() -> Bool { true }"))
  assert_true(first.entry != second.entry)
  assert_true(
    first.entry.local_name !=
    @ir.Name::from_words(["frontend", "temporary", "0"]),
  )
}

///|
test "default function visibility remains unexported" {
  let output = @frontend.compile(input("fn hidden() -> Bool { true }"))
  assert_false(output.public)
  let generated = @generator.generate({
    unit_id: output.unit_id,
    ir: output.ir,
    metadata: [],
    annotations: output.annotations,
    provenance: output.provenance,
  })
  assert_false(generated.symbols[0].public)
}

///|
test "Ion origins and provenance survive generated symbol storage" {
  let output = @frontend.compile(
    input("// λ😀\n" + definition("active && vip")),
  )
  let generated = @generator.generate({
    unit_id: output.unit_id,
    ir: output.ir,
    metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
    annotations: output.annotations,
    provenance: output.provenance,
  })
  let artifact = generated.artifacts.filter(a => a.path == "symbols.10n")[0]
  guard artifact.content is @generator.Binary(bytes) else {
    fail("Expected binary Ion")
  }
  let stored = @ion_binary.read_binary_value(bytes[:])
  assert_eq(@ion_binary.write_binary_value(stored), bytes)
  guard stored.kind() is @ion.Struct(fields) else {
    fail("Expected symbol record")
  }
  let by_name = Map([])
  for field in fields {
    by_name[field.name().text().unwrap()] = field.value()
  }
  assert_true(
    by_name["source_provenance"].equals(@ion.IonValue::list(output.provenance)),
  )
  guard by_name["metadata"].kind() is @ion.List(entries) else {
    fail("Expected origins")
  }
  assert_eq(entries.length(), output.metadata.length())
  for (entry, expected) in entries.zip(output.metadata) {
    guard entry.kind() is @ion.Struct(origin_fields) else {
      fail("Expected origin record")
    }
    assert_true(
      origin_fields[0].value().equals(@ion.IonValue::string(expected.node_id)),
    )
    assert_true(origin_fields[1].value().equals(expected.data))
  }
  assert_eq(output.metadata.length(), 2)
  assert_true(generated.symbols[0].origins.contains(output.metadata[0].node_id))
}

///|
test "empty models and invalid logical identities fail" {
  assert_eq(failure("").code, "moonbit_frontend.declaration_count")
  for value in ["", "Main", "bad#name"] {
    try {
      ignore(
        @frontend.compile({ ..input(definition("active")), module_name: value, }),
      )
      fail("Expected invalid module identity")
    } catch {
      @frontend.Invalid(diagnostic) =>
        assert_eq(diagnostic.code, "moonbit_frontend.invalid_identity")
      error => raise error
    }
  }
}

///|
test "limits and cancellation fail explicitly" {
  let source = input(definition("active && vip"))
  for
    (limits, code) in [
      ({ ..@frontend.Limits::default(), max_bytes: 1, }, "byte_limit"),
      ({ ..@frontend.Limits::default(), max_parameters: 1, }, "parameter_limit"),
      (
        { ..@frontend.Limits::default(), max_expressions: 1, },
        "expression_limit",
      ),
      ({ ..@frontend.Limits::default(), max_depth: 0, }, "expression_limit"),
      ({ ..@frontend.Limits::default(), max_depth: 65, }, "invalid_limits"),
    ] {
    try {
      ignore(@frontend.compile(source, limits~))
      fail("Expected a budget failure")
    } catch {
      @frontend.Invalid(diagnostic) =>
        assert_eq(diagnostic.code, "moonbit_frontend." + code)
      error => raise error
    }
  }
  let mut ticks = 0
  try {
    ignore(
      @frontend.compile(source, cancelled=fn() {
        ticks += 1
        ticks > 2
      }),
    )
    fail("Expected cancellation during traversal")
  } catch {
    @frontend.Invalid(diagnostic) =>
      assert_eq(diagnostic.code, "moonbit_frontend.cancelled")
    error => raise error
  }
}
