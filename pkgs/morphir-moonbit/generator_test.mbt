///|
fn single(
  output : @ir.Type,
  body : @ir.Value,
  definition? : @ir.ValueDefinition? = None,
) -> @generator.Input raise {
  let name = @ir.Name::parse("value")
  let value : @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]] = match
    definition {
    Some(definition) =>
      { access: @ir.Access::Public, value: { doc: None, value: definition, }, }
    None => @fixtures.definition(output, body)
  }
  let module_def : @ir.ModuleDefinition = {
    types: Map([]),
    doc: None,
    values: Map::from_array([(name, value)]),
  }
  @generator.Input::new(
    "single",
    @ir.IRFile::new(
      @ir.Distribution::Library(@ir.Path::parse("sample"), Map([]), {
        modules: Map::from_array([
          (
            @ir.Path::parse("main"),
            { access: @ir.Access::Public, value: module_def, },
          ),
        ]),
      }),
    ),
  )
}

///|
fn error(input : @generator.Input) -> (String, String) {
  try {
    ignore(@generator.generate(input))
    ("", "")
  } catch {
    @generator.Invalid(code, context, _) => (code, context)
  }
}

///|
test "deterministic flattened library preserves public and private symbols" {
  let result = @generator.generate(
    @generator.Input::new("scalars", @fixtures.library()),
  )
  let reordered = @generator.generate(
    @generator.Input::new("scalars", @fixtures.library(reverse=true)),
  )
  assert_eq(result.artifacts, reordered.artifacts)
  assert_eq(result.project, reordered.project)
  assert_eq(result.symbols, reordered.symbols)
  assert_eq(result.symbols.length(), 13)
  assert_eq(result.project.members, [
    "moon.mod", "moon.pkg", "library.mbt", "symbols.10n",
  ])
  assert_true(
    result.symbols.any(s => s.fqname == "pricing:internal#secret" && !s.public),
  )
  assert_true(
    result.symbols.any(s => s.fqname == "pricing:scalars#hidden" && !s.public),
  )
  assert_true(
    result.symbols.any(s => s.fqname == "pricing:other#copy" && s.public),
  )
  assert_eq(
    result.project.dependencies[0].api_profile,
    "morphir-sdk-concrete-v1",
  )
}

///|
test "FQName encoding distinguishes initialisms words package and module boundaries" {
  let identities = [
    "example:main#SDK", "example:main#sdk", "example:main#s-d-k", "example:main#s-dk",
    "example/main:other#sdk", "example:main/other#sdk",
  ]
  let names = Map([])
  for identity in identities {
    let name = @generator.value_name(@ir.FQName::parse(identity))
    assert_false(names.contains(name))
    assert_true(name.has_prefix("v_"))
    names[name] = true
  }
  let malformed : @ir.FQName = {
    package_name: @ir.Path::parse("example"),
    module_name: @ir.Path::parse("main"),
    local_name: @ir.Name::from_words(["SDK"]),
  }
  assert_true(
    try {
      ignore(@generator.value_name(malformed))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "exact decimal construction refuses SDK truncation and float bits remain exact" {
  let decimal = @fixtures.scalar("morphir/SDK:decimal#decimal")
  let valid = single(
    decimal,
    @ir.Value::Literal(
      @fixtures.attrs(),
      @ir.Literal::DecimalLiteral("1.000000000000000000000000000000000"),
    ),
  )
  assert_eq(error(valid).0, "")
  let loss = single(
    decimal,
    @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::DecimalLiteral("1e-33")),
  )
  assert_eq(
    error(loss),
    ("moonbit.literal_precision_loss", "value:sample:main#value/body"),
  )
  let zero = single(
    decimal,
    @ir.Value::Literal(
      @fixtures.attrs(),
      @ir.Literal::DecimalLiteral("-0.000000000000000000000000000000000"),
    ),
  )
  assert_eq(error(zero).0, "")
  let out = @generator.generate(
    @generator.Input::new("scalars", @fixtures.library()),
  )
  let source = match out.artifacts[2].content {
    Text(s) => s
    Binary(_) => fail("Expected source")
  }
  assert_true(source.contains("9223372036854775808UL"))
  assert_true(source.contains("(1UL).reinterpret_as_double()"))
  assert_true(
    source.contains(
      "@integer.parse(\"1234567890123456789012345678901234567890\")",
    ),
  )
}

///|
test "declared and inferred types must agree with scalar bodies" {
  let boolean = @fixtures.scalar("morphir/SDK:basics#bool")
  let integer = @fixtures.scalar("morphir/SDK:basics#int")
  let mismatch = single(
    boolean,
    @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("1")),
  )
  assert_eq(error(mismatch).0, "moonbit.type_mismatch")
  let inferred = { ..@fixtures.attrs(), inferred_type: Some(integer), }
  assert_eq(
    error(
      single(
        boolean,
        @ir.Value::Literal(inferred, @ir.Literal::BoolLiteral(true)),
      ),
    ).0,
    "moonbit.type_mismatch",
  )
  let ambiguous = @ir.Type::Variable(
    { source: None, constraints: Map([]), extensions: Map([]), },
    @ir.Name::parse("number"),
  )
  assert_eq(
    error(
      single(
        ambiguous,
        @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("1")),
      ),
    ).0,
    "moonbit.ambiguous_type",
  )
  let unknown = @fixtures.scalar("morphir/sdk:basics#int")
  assert_eq(
    error(
      single(
        unknown,
        @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::IntegerLiteral("1")),
      ),
    ).0,
    "moonbit.unsupported_type",
  )
}

///|
test "unsupported distributions bodies and unresolved references fail contextually" {
  let boolean = @fixtures.scalar("morphir/SDK:basics#bool")
  let hole = @ir.Value::Hole(
    @fixtures.attrs(),
    @ir.HoleReason::DeletedDuringRefactor("missing"),
    None,
  )
  assert_eq(error(single(boolean, hole)).0, "moonbit.incomplete_body")
  let reference = @ir.Value::Reference(
    @fixtures.attrs(),
    @ir.FQName::parse("other:main#missing"),
  )
  assert_eq(error(single(boolean, reference)).0, "moonbit.unresolved_reference")
  let specs = @ir.IRFile::new(
    @ir.Distribution::Specs(@ir.Path::parse("sample"), Map([]), {
      modules: Map([]),
    }),
  )
  assert_eq(
    error(@generator.Input::new("specs", specs)).0,
    "moonbit.unsupported_distribution",
  )
  for
    (definition, code) in [
      (
        @ir.ValueDefinition::IncompleteBody(
          [],
          Some(boolean),
          @ir.Incompleteness::Draft,
          None,
        ),
        "moonbit.incomplete_body",
      ),
      (
        @ir.ValueDefinition::NativeBody([], boolean, {
          hint: @ir.NativeHint::Arithmetic,
          description: None,
        }),
        "moonbit.unresolved_implementation",
      ),
      (
        @ir.ValueDefinition::ExternalBody(
          [],
          boolean,
          [{ target_platform: "moonbit", external_name: "unknown", }],
          Some(hole),
        ),
        "moonbit.unresolved_implementation",
      ),
      (
        @ir.ValueDefinition::ExpressionBody(
          [(@ir.Name::parse("input"), boolean)],
          boolean,
          hole,
        ),
        "moonbit.incomplete_body",
      ),
    ] {
    assert_eq(error(single(boolean, hole, definition=Some(definition))).0, code)
  }
  let document = @ir.Value::Literal(
    @fixtures.attrs(),
    @ir.Literal::DocumentLiteral(@ir.Data::Null),
  )
  assert_eq(error(single(boolean, document)).0, "moonbit.unsupported_literal")
  let ir = @fixtures.library()
  guard ir.distribution is Library(name, deps, def) else {
    fail("Expected library")
  }
  let modules = def.modules.copy()
  let module_name = @ir.Path::parse("other")
  let module_def = modules[module_name]
  let values = module_def.value.values.copy()
  values[@ir.Name::parse("copy")] = @fixtures.definition(
    boolean,
    @ir.Value::Reference(
      @fixtures.attrs(),
      @ir.FQName::parse("pricing:scalars#hidden"),
    ),
  )
  modules[module_name] = {
    ..module_def,
    value: { ..module_def.value, values, },
  }
  assert_eq(
    error(
      @generator.Input::new(
        "private",
        @ir.IRFile::new(@ir.Distribution::Library(name, deps, { modules, })),
      ),
    ).0,
    "moonbit.inaccessible_reference",
  )
}

///|
test "Ion symbols retain node metadata ordered annotations and source lexemes" {
  let data = @ion_text.read_ion(
    "unknown::unknown::{scale:12.340d0,blob:{{/wCA}},nil:null.int,fields:{a:1,a:2}}",
  )
  let input = {
    ..@generator.Input::new("scalars", @fixtures.library()),
    annotations: [
      @ion.SymbolToken::new("audit"),
      @ion.SymbolToken::new("audit"),
    ],
    metadata: [{ node_id: "value:pricing:scalars#rate/body", data, }],
  }
  let result = @generator.generate(input)
  let bytes = match result.artifacts[3].content {
    Binary(bytes) => bytes
    Text(_) => fail("Expected binary metadata")
  }
  let value = @ion_binary.read_binary_value(bytes[:])
  guard value.kind() is Struct(fields) else { fail("Expected symbol profile") }
  let by_name = Map([])
  for field in fields {
    by_name[field.name().text().unwrap()] = field.value()
  }
  guard by_name["metadata"].kind() is List([entry]) else {
    fail("Expected metadata")
  }
  guard entry.kind() is Struct(metadata_fields) else { fail("Expected entry") }
  let retained = metadata_fields[1].value()
  assert_true(retained.equals(data))
  assert_eq(retained.annotations().map(token => token.text()), [
    Some("unknown"),
    Some("unknown"),
  ])
  guard by_name["source_ir_json"].kind() is String(source) else {
    fail("Expected source snapshot")
  }
  assert_true(source.contains("+12.3400E-2"))
  assert_true(
    result.symbols.any(symbol => {
      symbol.origins.contains("value:pricing:scalars#rate/body")
    }),
  )
  let invalid = { ..input, metadata: [{ node_id: "unknown", data, }], }
  assert_eq(error(invalid).0, "moonbit.metadata_identity")
}

///|
test "limits and cancellation stop generation before it returns artifacts" {
  let input = @generator.Input::new("scalars", @fixtures.library())
  let failure = try {
    ignore(
      @generator.generate(
        input,
        limits=Some({ max_declarations: 1, max_bytes: 100000, }),
      ),
    )
    ""
  } catch {
    @generator.Invalid(code, _, _) => code
  }
  assert_eq(failure, "moonbit.declaration_limit")
  let failure = try {
    ignore(
      @generator.generate(
        input,
        limits=Some({ max_declarations: 100, max_bytes: 20, }),
      ),
    )
    ""
  } catch {
    @generator.Invalid(code, _, _) => code
  }
  assert_eq(failure, "moonbit.byte_limit")
  let failure = try {
    ignore(@generator.generate(input, cancelled=fn() { true }))
    ""
  } catch {
    @generator.Invalid(code, _, _) => code
  }
  assert_eq(failure, "moonbit.cancelled")
}

///|
test "multi module pricing lowers concrete records functions and constructors" {
  let output = @generator.generate(
    @generator.Input::new("pricing", @fixtures.pricing()),
  )
  assert_eq(output.symbols.length(), 28)
  assert_true(output.symbols.any(s => s.fqname == "pricing:results#mapped-sum"))
}

///|
test "compound lowering rejects generic open and unsupported SDK types" {
  let a : @ir.TypeAttributes = {
    source: None,
    constraints: Map([]),
    extensions: Map([]),
  }
  let open = @ir.Type::ExtensibleRecord(a, @ir.Name::parse("row"), Map([]))
  assert_eq(
    error(single(open, @ir.Value::Unit(@fixtures.attrs()))).0,
    "moonbit.unsupported_type",
  )
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let unknown = @ir.Value::Reference(
    { ..@fixtures.attrs(), inferred_type: Some(int), },
    @ir.FQName::parse("morphir/SDK:basics#unknown"),
  )
  assert_eq(error(single(int, unknown)).0, "moonbit.unsupported_sdk")
  let function = @ir.Type::Function(a, int, int)
  let wrong = @ir.Value::Reference(
    { ..@fixtures.attrs(), inferred_type: Some(function), },
    @ir.FQName::parse("morphir/SDK:basics#add"),
  )
  assert_eq(error(single(function, wrong)).0, "moonbit.sdk_signature")
}

///|
test "tuples lists maybe and result use concrete type parameter order" {
  let a : @ir.TypeAttributes = {
    source: None,
    constraints: Map([]),
    extensions: Map([]),
  }
  let int = @fixtures.scalar("morphir/SDK:basics#int")
  let bool = @fixtures.scalar("morphir/SDK:basics#bool")
  let one = @ir.Value::Literal(
    @fixtures.attrs(),
    @ir.Literal::IntegerLiteral("1"),
  )
  let tuple = @ir.Type::Tuple(a, [int, bool])
  assert_eq(
    error(
      single(
        tuple,
        @ir.Value::Tuple(@fixtures.attrs(), [
          one,
          @ir.Value::Literal(@fixtures.attrs(), @ir.Literal::BoolLiteral(true)),
        ]),
      ),
    ).0,
    "",
  )
  let list = @ir.Type::Reference(
    a,
    @ir.FQName::parse("morphir/SDK:list#list"),
    [int],
  )
  assert_eq(
    error(single(list, @ir.Value::List(@fixtures.attrs(), [one]))).0,
    "",
  )
  let maybe = @ir.Type::Reference(
    a,
    @ir.FQName::parse("morphir/SDK:maybe#maybe"),
    [int],
  )
  assert_eq(
    error(
      single(
        maybe,
        @ir.Value::Constructor(
          @fixtures.attrs(),
          @ir.FQName::parse("morphir/SDK:maybe#nothing"),
        ),
      ),
    ).0,
    "",
  )
  let result = @ir.Type::Reference(
    a,
    @ir.FQName::parse("morphir/SDK:result#result"),
    [bool, int],
  )
  let constructor = @ir.Value::Constructor(
    {
      ..@fixtures.attrs(),
      inferred_type: Some(@ir.Type::Function(a, int, result)),
    },
    @ir.FQName::parse("morphir/SDK:result#ok"),
  )
  let out = @generator.generate(
    single(result, @ir.Value::Apply(@fixtures.attrs(), constructor, one)),
  )
  guard out.artifacts[2].content is Text(source) else { fail("source") }
  assert_true(source.contains("Result[@integer.Integer, Bool]"))
}
