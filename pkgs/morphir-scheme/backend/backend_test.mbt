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
