///|
fn attrs() -> @ir.ValueAttributes {
  @ir.ValueAttributes::default()
}

///|
fn int(n : String) -> @ir.Value {
  @ir.Value::Literal(attrs(), @ir.Literal::IntegerLiteral(n))
}

///|
fn name(s : String) -> @ir.Name raise {
  @ir.Name::parse(s)
}

///|
fn bind(s : String) -> @ir.Pattern raise {
  @ir.Pattern::AsPattern(
    attrs(),
    @ir.Pattern::WildcardPattern(attrs()),
    name(s),
  )
}

///|
fn run(value : @ir.Value) -> String raise {
  @scheme.value_to_string(@backend.evaluate(value))
}

///|
fn sdk_call(
  name : String,
  left : @ir.Value,
  right : @ir.Value,
) -> @ir.Value raise {
  let a = attrs()
  @ir.Value::Apply(
    a,
    @ir.Value::Apply(
      a,
      @ir.Value::Reference(a, @ir.FQName::parse("morphir/SDK:basics#" + name)),
      left,
    ),
    right,
  )
}

///|
fn sdk_apply_ir(name : String, arguments : Array[@ir.Value]) -> @ir.Value raise {
  let a = attrs()
  let mut call = @ir.Value::Reference(a, @ir.FQName::parse(name))
  for argument in arguments {
    call = @ir.Value::Apply(a, call, argument)
  }
  call
}

///|
fn compare_sdk_paths(value : @ir.Value, expected : String) -> Unit raise {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let direct = @scheme.value_to_string(@backend.evaluate_in(runtime, value))
  let emitted = @scheme.value_to_string(
    runtime.eval(@backend.emit_expression(value)),
  )
  assert_eq(direct, emitted)
  assert_eq(direct, expected)
}

///|
test "IR Scheme paths agree on curried collection callbacks" {
  let a = attrs()
  let x = @ir.Value::Variable(a, name("x"))
  let increment = @ir.Value::Lambda(
    a,
    bind("x"),
    sdk_apply_ir("morphir/SDK:basics#add", [x, int("1")]),
  )
  let mapped = sdk_apply_ir("morphir/SDK:list#map", [
    increment,
    @ir.Value::List(a, [int("1"), int("2"), int("3")]),
  ])
  compare_sdk_paths(mapped, "(2 3 4)")
  let maybe = sdk_apply_ir("morphir/SDK:maybe#map", [
    increment,
    @ir.Value::Apply(
      a,
      @ir.Value::Constructor(a, @ir.FQName::parse("morphir/SDK:maybe#just")),
      int("41"),
    ),
  ])
  compare_sdk_paths(maybe, "#<morphir/SDK:maybe#just 42>")
}

///|
test "IR Scheme paths agree on ordered Dict and Set values" {
  let a = attrs()
  let pairs = @ir.Value::List(a, [
    @ir.Value::Tuple(a, [int("2"), int("20")]),
    @ir.Value::Tuple(a, [int("1"), int("10")]),
  ])
  let dict = sdk_apply_ir("morphir/SDK:dict#from-list", [pairs])
  compare_sdk_paths(sdk_apply_ir("morphir/SDK:dict#keys", [dict]), "(1 2)")
  let set = sdk_apply_ir("morphir/SDK:set#from-list", [
    @ir.Value::List(a, [int("2"), int("1"), int("2")]),
  ])
  compare_sdk_paths(sdk_apply_ir("morphir/SDK:set#to-list", [set]), "(1 2)")
}

///|
test "SDK boolean operators skip the unused branch in both paths" {
  let a = attrs()
  let bad = sdk_apply_ir("morphir/SDK:basics#equal", [
    sdk_apply_ir("morphir/SDK:basics#integer-divide", [int("1"), int("0")]),
    int("0"),
  ])
  let and_call = sdk_apply_ir("morphir/SDK:basics#and", [
    @ir.Value::Literal(a, @ir.Literal::BoolLiteral(false)),
    bad,
  ])
  let or_call = sdk_apply_ir("morphir/SDK:basics#or", [
    @ir.Value::Literal(a, @ir.Literal::BoolLiteral(true)),
    bad,
  ])
  compare_sdk_paths(and_call, "#f")
  compare_sdk_paths(or_call, "#t")
}

///|
test "IR SDK arithmetic uses typed SDK rules inside Scheme" {
  let quotient = sdk_call("integer-divide", int("-7"), int("3"))
  assert_eq(
    run(quotient),
    @integer.to_string(
      @basics.integer_divide(@integer.from_int(-7), @integer.from_int(3)),
    ),
  )
  assert_eq(run(sdk_call("mod-by", int("3"), int("-7"))), "2")
  let float_value = @backend.evaluate(
    sdk_call(
      "divide",
      @ir.Value::Literal(attrs(), @ir.Literal::FloatLiteral(1.0)),
      @ir.Value::Literal(attrs(), @ir.Literal::FloatLiteral(2.0)),
    ),
  )
  match float_value {
    @scheme.Number(@scheme.Number::Real(value)) =>
      assert_eq(value, @basics.divide(1.0, 2.0))
    _ => abort("Expected SDK Float result")
  }
  let invalid = try {
    ignore(@backend.evaluate(sdk_call("integer-divide", int("1"), int("0"))))
    false
  } catch {
    @scheme.Invalid(message) => message.contains("division by zero")
    _ => false
  }
  assert_true(invalid)
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let emitted_invalid = try {
    ignore(
      runtime.eval(
        @backend.emit_expression(sdk_call("integer-divide", int("1"), int("0"))),
      ),
    )
    false
  } catch {
    @scheme.Invalid(message) => message.contains("division by zero")
    _ => false
  }
  assert_true(emitted_invalid)
  assert_eq(
    @scheme.value_to_string(@scheme.Runtime::new().eval("(/ 1 2)")),
    "1/2",
  )
}

///|
test "IR SDK String append uses the UTF-16 SDK" {
  let a = attrs()
  let string = fn(value : String) -> @ir.Value {
    @ir.Value::Literal(a, @ir.Literal::StringLiteral(value))
  }
  let call = @ir.Value::Apply(
    a,
    @ir.Value::Apply(
      a,
      @ir.Value::Reference(a, @ir.FQName::parse("morphir/SDK:string#append")),
      string("a😀"),
    ),
    string("b"),
  )
  assert_eq(run(call), "\"a😀b\"")
}

///|
test "record updates field functions and tuple destructuring" {
  let record = @ir.Value::Record(
    attrs(),
    Map::from_array([(name("answer"), int("40"))]),
  )
  let updated = @ir.Value::UpdateRecord(
    attrs(),
    record,
    Map::from_array([(name("answer"), int("42"))]),
  )
  assert_eq(run(@ir.Value::Field(attrs(), updated, name("answer"))), "42")
  assert_eq(
    run(
      @ir.Value::Apply(
        attrs(),
        @ir.Value::FieldFunction(attrs(), name("answer")),
        record,
      ),
    ),
    "40",
  )
  let tuple = @ir.Value::Tuple(attrs(), [int("42"), @ir.Value::Unit(attrs())])
  let pattern = @ir.Pattern::TuplePattern(attrs(), [
    bind("x"),
    @ir.Pattern::UnitPattern(attrs()),
  ])
  assert_eq(
    run(
      @ir.Value::Destructure(
        attrs(),
        pattern,
        tuple,
        @ir.Value::Variable(attrs(), name("x")),
      ),
    ),
    "42",
  )
}

///|
test "pattern matching supports list and constructor shapes" {
  let a = attrs()
  let variable = @ir.Value::Variable(a, name("x"))
  let list = @ir.Value::List(a, [int("42")])
  let cases = [
    (@ir.Pattern::EmptyListPattern(a), int("0")),
    (
      @ir.Pattern::HeadTailPattern(
        a,
        bind("x"),
        @ir.Pattern::EmptyListPattern(a),
      ),
      variable,
    ),
  ]
  assert_eq(run(@ir.Value::PatternMatch(a, list, cases)), "42")
  let just = @ir.FQName::parse("morphir/SDK:maybe#just")
  let target = @ir.Value::Apply(a, @ir.Value::Constructor(a, just), int("42"))
  assert_eq(
    run(
      @ir.Value::PatternMatch(a, target, [
        (@ir.Pattern::ConstructorPattern(a, just, [bind("x")]), variable),
      ]),
    ),
    "42",
  )
  assert_eq(
    run(
      @ir.Value::PatternMatch(a, int("42"), [
        (
          @ir.Pattern::LiteralPattern(
            a,
            @ir.PatternLiteral::IntegerLiteral("42"),
          ),
          int("1"),
        ),
      ]),
    ),
    "1",
  )
}

///|
fn file(definition : @ir.ValueDefinition) -> @ir.IRFile raise {
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map::from_array([
    (
      name("main"),
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
test "external and native definitions use explicit host registrations" {
  let output = @ir.Type::Unit(@ir.TypeAttributes::default())
  let external = @ir.ValueDefinition::ExternalBody(
    [],
    output,
    [{ target_platform: "morphir-scheme", external_name: "answer", }],
    None,
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  runtime.define_native("external:answer", fn(_rt, args) raise {
    @scheme.arity(args, 0, "answer")
    @scheme.integer("42")
  })
  ignore(runtime.eval(@backend.emit_file(file(external))))
  let entry = @ir.FQName::parse("test:main#main")
  assert_eq(
    @scheme.value_to_string(@backend.call_entry(runtime, entry, [])),
    "42",
  )
  let native = @ir.ValueDefinition::NativeBody([], output, {
    hint: @ir.NativeHint::Arithmetic,
    description: None,
  })
  @backend.register_native(runtime, entry, fn(_rt, _args) raise {
    @scheme.integer("43")
  })
  ignore(runtime.eval(@backend.emit_file(file(native))))
  assert_eq(
    @scheme.value_to_string(@backend.call_entry(runtime, entry, [])),
    "43",
  )
  let fallback = @ir.ValueDefinition::ExternalBody(
    [],
    output,
    [],
    Some(int("44")),
  )
  assert_eq(
    @scheme.value_to_string(@backend.run_file(file(fallback), entry, [])),
    "44",
  )
}

///|
test "hybrid external binding selects native or portable body" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::ExternalBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    [{ target_platform: "morphir-runtime", external_name: "answer", }],
    Some(int("44")),
  )
  let portable = @backend.run_file(file(definition), entry, [])
  assert_eq(@scheme.value_to_string(portable), "44")

  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_external(runtime, "answer", 0, fn(_rt, _args) raise {
    @scheme.integer("42")
  })
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file_in(runtime, file(definition), entry, []),
    ),
    "42",
  )
  ignore(runtime.eval(@backend.emit_file(file(definition))))
  assert_eq(
    @scheme.value_to_string(@backend.call_entry(runtime, entry, [])),
    "42",
  )
}

///|
test "hybrid resolution skips unavailable targets in declaration order" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::ExternalBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    [
      { target_platform: "javascript", external_name: "wrong-target", },
      { target_platform: "morphir-runtime", external_name: "absent", },
      { target_platform: "morphir-scheme", external_name: "available", },
    ],
    Some(int("44")),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_external(runtime, "available", 0, fn(_rt, _args) raise {
    @scheme.integer("42")
  })
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file_in(runtime, file(definition), entry, []),
    ),
    "42",
  )
  ignore(runtime.eval(@backend.emit_file(file(definition))))
  assert_eq(
    @scheme.value_to_string(@backend.call_entry(runtime, entry, [])),
    "42",
  )
}

///|
test "linking rejects mismatched native arity before execution" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::ExpressionBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    int("44"),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_accelerator(runtime, entry, 1, fn(_rt, _args) raise {
    @scheme.integer("42")
  })
  let mismatch = try {
    @backend.link_file(runtime, file(definition))
    false
  } catch {
    @scheme.Invalid(message) => message.contains("arity mismatch")
    _ => false
  }
  assert_true(mismatch)
}

///|
test "portable definitions permit an explicit native accelerator" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::ExpressionBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    int("44"),
  )
  assert_eq(
    @scheme.value_to_string(@backend.run_file(file(definition), entry, [])),
    "44",
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_accelerator(runtime, entry, 0, fn(_rt, _args) raise {
    @scheme.integer("45")
  })
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file_in(runtime, file(definition), entry, []),
    ),
    "45",
  )
  ignore(runtime.eval(@backend.emit_file(file(definition))))
  assert_eq(
    @scheme.value_to_string(@backend.call_entry(runtime, entry, [])),
    "45",
  )
  let duplicate = try {
    @backend.register_accelerator(runtime, entry, 0, fn(_rt, _args) raise {
      @scheme.integer("46")
    })
    false
  } catch {
    @scheme.Invalid(_) => true
    _ => false
  }
  assert_true(duplicate)
  @backend.replace_accelerator(runtime, entry, 0, fn(_rt, _args) raise {
    @scheme.integer("46")
  })
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file_in(runtime, file(definition), entry, []),
    ),
    "46",
  )
}

///|
test "invoked native errors do not execute a portable fallback" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::ExternalBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    [{ target_platform: "morphir-runtime", external_name: "fails", }],
    Some(int("44")),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_external(runtime, "fails", 0, fn(_rt, _args) raise {
    raise @scheme.Invalid("native failed")
  })
  let failed = try {
    ignore(@backend.run_file_in(runtime, file(definition), entry, []))
    false
  } catch {
    @scheme.Invalid(message) => message == "native failed"
    _ => false
  }
  assert_true(failed)
}

///|
test "native bodies require bindings and direct calls retain limits" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::NativeBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    { hint: @ir.NativeHint::Arithmetic, description: None, },
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let missing = try {
    @backend.link_file(runtime, file(definition))
    false
  } catch {
    @scheme.Unbound(_) => true
    _ => false
  }
  assert_true(missing)
  @backend.register_native(runtime, entry, fn(_rt, _args) raise {
    @scheme.integer("42")
  })
  assert_eq(
    @scheme.value_to_string(
      @backend.run_file_in(runtime, file(definition), entry, []),
    ),
    "42",
  )
  runtime.set_cancelled(fn() { true })
  let cancelled = try {
    ignore(@backend.run_file_in(runtime, file(definition), entry, []))
    false
  } catch {
    @scheme.Limit("cancelled") => true
    _ => false
  }
  assert_true(cancelled)
}

///|
test "direct native calls can invoke higher-order Scheme callbacks" {
  let entry = @ir.FQName::parse("test:main#callback")
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_accelerator(runtime, entry, 2, fn(rt, args) raise {
    rt.call(args[0], [args[1]])
  })
  let lambda = @ir.Value::Lambda(
    attrs(),
    bind("x"),
    @ir.Value::Variable(attrs(), name("x")),
  )
  let call = @ir.Value::Apply(
    attrs(),
    @ir.Value::Apply(attrs(), @ir.Value::Reference(attrs(), entry), lambda),
    int("42"),
  )
  assert_eq(@scheme.value_to_string(@backend.evaluate_in(runtime, call)), "42")
}

///|
test "invalid execution states fail explicitly" {
  let a = attrs()
  for
    value in [
      @ir.Value::IfThenElse(a, int("1"), int("2"), int("3")),
      @ir.Value::PatternMatch(a, int("1"), []),
      @ir.Value::UpdateRecord(
        a,
        @ir.Value::Record(a, Map([])),
        Map::from_array([(name("x"), int("1"))]),
      ),
    ] {
    let refused = try {
      ignore(@backend.evaluate(value))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  let hole = @ir.Value::Hole(
    a,
    @ir.HoleReason::DeletedDuringRefactor("todo"),
    None,
  )
  let refused = try {
    ignore(@backend.emit_expression(hole))
    false
  } catch {
    @scheme.Unsupported(_) => true
    _ => false
  }
  assert_true(refused)
}
