///|
fn int_type() -> @ir.Type {
  ref_type("morphir/SDK:basics#int")
}

///|
fn defined(
  name : String,
  access : @ir.Access,
  doc : String?,
  definition : @ir.ValueDefinition,
) -> (@ir.Name, @ir.Access, String?, ValueSource) {
  (n(name), access, doc, DefinedValue(definition))
}

///|
fn module_with(
  values : Array[(@ir.Name, @ir.Access, String?, ValueSource)],
  doc? : String? = None,
  entry_points? : Map[String, @ir.EntryPoint] = Map([]),
) -> ModuleInput {
  {
    package_name: @ir.Path::parse("acme/app") catch {
      _ => panic()
    },
    module: @ir.Path::parse("orders") catch {
      _ => panic()
    },
    doc,
    types: [],
    values,
    entry_points,
  }
}

///|
fn module_code(options : Options, input : ModuleInput) -> String {
  try {
    ignore(generate_module(options, input))
    ""
  } catch {
    Refused(problem) => problem.code + " " + problem.node_path
    _ => "other"
  }
}

///|
test "a module prints with signatures, docs, exposing and imports" {
  let double = defined(
    "double",
    Public,
    Some("Twice the input."),
    ExpressionBody(
      [(n("x"), int_type())],
      int_type(),
      apply(sdk("morphir/SDK:basics#multiply"), [variable("x"), int("2")]),
    ),
  )
  let helper = defined(
    "helper",
    Private,
    None,
    ExpressionBody(
      [],
      ref_type("morphir/SDK:dict#dict", args=[int_type(), int_type()]),
      sdk("morphir/SDK:dict#empty"),
    ),
  )
  let output = generate_module(
    Options::default(),
    module_with([double, helper], doc=Some("Orders.")),
  )
  let source = output.source
  assert_eq(output.elm_module, ["Acme", "App", "Orders"])
  assert_true(source.has_prefix("module Acme.App.Orders exposing (double)\n"))
  assert_true(source.contains("import Dict\n"))
  assert_true(
    source.contains(
      "{-| Twice the input.\n-}\ndouble : Int -> Int\ndouble x =\n    x * 2",
    ),
  )
  assert_true(
    source.contains("helper : Dict.Dict Int Int\nhelper =\n    Dict.empty"),
  )
  let parsed = @krueger.parse_module(@krueger.SourceText::new(source))
  assert_true(parsed.diagnostics.is_empty())
}

///|
test "module documentation is printed" {
  let value = defined(
    "answer",
    Public,
    None,
    ExpressionBody([], int_type(), int("42")),
  )
  let source = generate_module(
      Options::default(),
      module_with([value], doc=Some("Orders.")),
    ).source
  assert_true(source.contains("{-| Orders.\n-}"))
}

///|
test "documentation that contains the comment end is escaped" {
  let value = defined(
    "answer",
    Public,
    Some("Ends here -} not really"),
    ExpressionBody([], int_type(), int("42")),
  )
  let source = generate_module(Options::default(), module_with([value])).source
  assert_true(source.contains("Ends here - } not really"))
  assert_true(
    @krueger.parse_module(@krueger.SourceText::new(source)).diagnostics.is_empty(),
  )
}

///|
test "a module with no public members exposes everything" {
  let value = defined(
    "answer",
    Private,
    None,
    ExpressionBody([], int_type(), int("42")),
  )
  let source = generate_module(Options::default(), module_with([value])).source
  assert_true(source.has_prefix("module Acme.App.Orders exposing (..)\n"))
}

///|
test "two IR names with one Elm name are refused" {
  let first = defined(
    "x-BC",
    Public,
    None,
    ExpressionBody([], int_type(), int("1")),
  )
  let second = defined(
    "x-B-C",
    Public,
    None,
    ExpressionBody([], int_type(), int("2")),
  )
  // Both print as xBC.
  assert_eq(
    module_code(Options::default(), module_with([first, second])),
    "elm.name_collision acme/app:orders#x-B-C",
  )
}

///|
test "placeholders follow the policy" {
  let native = defined(
    "native",
    Public,
    None,
    NativeBody([(n("x"), int_type())], int_type(), {
      hint: Arithmetic,
      description: None,
    }),
  )
  assert_eq(
    module_code(Options::default(), module_with([native])),
    "elm.placeholder acme/app:orders#native",
  )
  let source = generate_module(
      { ..Options::default(), placeholders: DebugTodo, },
      module_with([native]),
    ).source
  assert_true(
    source.contains(
      "native : Int -> Int\nnative x =\n    Debug.todo \"native body\"",
    ),
  )
  let incomplete = defined(
    "draft",
    Public,
    None,
    IncompleteBody([], None, Draft, None),
  )
  let draft = generate_module(
      { ..Options::default(), placeholders: DebugTodo, },
      module_with([incomplete]),
    ).source
  assert_true(
    draft.contains("draft =\n    Debug.todo \"incomplete definition\""),
  )
  assert_false(draft.contains("draft :"))
}

///|
test "external bodies keep the fallback and record bindings" {
  let external = defined(
    "now",
    Public,
    None,
    ExternalBody(
      [],
      int_type(),
      [{ target_platform: "jvm", external_name: "System.currentTimeMillis", }],
      Some(int("0")),
    ),
  )
  let source = generate_module(Options::default(), module_with([external])).source
  assert_true(
    source.contains(
      "@morphir.external { platform = \"jvm\", name = \"System.currentTimeMillis\" }",
    ),
  )
  assert_true(source.contains("now =\n    0"))
}

///|
test "entry points become attributes" {
  let main = defined(
    "main",
    Public,
    None,
    ExpressionBody([], int_type(), int("0")),
  )
  let entry : @ir.EntryPoint = {
    target: @ir.FQName::parse("acme/app:orders#main") catch {
      _ => panic()
    },
    kind: Main,
    doc: None,
  }
  let source = generate_module(
      Options::default(),
      module_with([main], entry_points=Map::from_array([("start", entry)])),
    ).source
  assert_true(
    source.contains("@morphir.entry { kind = \"main\", name = \"start\" }"),
  )
}

///|
test "print failures name the declaration" {
  // NaN cannot print as Elm.
  let bad = defined(
    "bad",
    Public,
    None,
    ExpressionBody(
      [],
      ref_type("morphir/SDK:basics#float"),
      @ir.Value::Literal(va(), FloatLiteral(0.0 / 0.0)),
    ),
  )
  assert_eq(
    module_code(Options::default(), module_with([bad])),
    "elm.print acme/app:orders#bad",
  )
}

///|
test "locals of different declarations do not share names" {
  let body = apply(sdk("morphir/SDK:basics#multiply"), [variable("x"), int("2")])
  let f = defined(
    "f",
    Public,
    None,
    ExpressionBody([(n("x"), int_type())], int_type(), body),
  )
  let g = defined(
    "g",
    Public,
    None,
    ExpressionBody([(n("x"), int_type())], int_type(), body),
  )
  let source = generate_module(Options::default(), module_with([f, g])).source
  assert_true(source.contains("f x =\n    x * 2"))
  assert_true(source.contains("g x =\n    x * 2"))
  assert_false(source.contains("x_1"))
}
