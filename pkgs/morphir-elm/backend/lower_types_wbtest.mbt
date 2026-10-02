///|
fn plain() -> @ir.TypeAttributes {
  { source: None, constraints: Map([]), extensions: Map([]), }
}

///|
fn ref_type(name : String, args? : Array[@ir.Type] = []) -> @ir.Type {
  @ir.Type::Reference(
    plain(),
    @ir.FQName::parse(name) catch {
      _ => panic()
    },
    args,
  )
}

///|
fn ctx_for(profile? : Profile = Model) -> Ctx {
  Ctx::new(
    { ..Options::default(), profile, },
    @ir.Path::parse("acme/app") catch {
      _ => panic()
    },
    @ir.Path::parse("orders") catch {
      _ => panic()
    },
  )
}

///|
fn show_type(ctx : Ctx, t : @ir.Type) -> String raise {
  @printer.print_type_annotation(node(lower_type(ctx, t, "t")))
}

///|
test "SDK types map to Elm core in the model profile" {
  let ctx = ctx_for()
  let int = ref_type("morphir/SDK:basics#int")
  assert_eq(show_type(ctx, int), "Int")
  assert_eq(
    show_type(
      ctx,
      ref_type("morphir/SDK:dict#dict", args=[
        ref_type("morphir/SDK:string#string"),
        int,
      ]),
    ),
    "Dict.Dict String Int",
  )
  assert_eq(show_type(ctx, @ir.Type::Function(plain(), int, int)), "Int -> Int")
  assert_eq(show_type(ctx, @ir.Type::Unit(plain())), "()")
  assert_eq(ctx.elm_imports().length(), 1) // Dict
  // Decimal is not elm/core: qualified, and the SDK Elm package is needed.
  assert_eq(
    show_type(ctx, ref_type("morphir/SDK:decimal#decimal")),
    "Morphir.SDK.Decimal.Decimal",
  )
  assert_true(ctx.uses_sdk_package)
}

///|
test "literal profile keeps every reference qualified" {
  let ctx = ctx_for(profile=Literal)
  assert_eq(
    show_type(ctx, ref_type("morphir/SDK:basics#int")),
    "Morphir.SDK.Basics.Int",
  )
}

///|
test "local references are unqualified and foreign packages are recorded" {
  let ctx = ctx_for()
  assert_eq(show_type(ctx, ref_type("acme/app:orders#order")), "Order")
  assert_eq(
    show_type(ctx, ref_type("acme/app:customers#customer")),
    "Acme.App.Customers.Customer",
  )
  assert_eq(
    show_type(ctx, ref_type("acme/common:money#money")),
    "Acme.Common.Money.Money",
  )
  assert_true(ctx.foreign_packages.contains("acme/common"))
  assert_false(ctx.foreign_packages.contains("acme/app"))
}

///|
test "records, extensible records and constrained variables" {
  let ctx = ctx_for()
  let int = ref_type("morphir/SDK:basics#int")
  let name = @ir.Name::parse
  let record = @ir.Type::Record(
    plain(),
    Map::from_array([(name("order-id") catch { _ => panic() }, int)]),
  )
  assert_eq(show_type(ctx, record), "{ orderId : Int }")
  let extensible = @ir.Type::ExtensibleRecord(
    plain(),
    name("r") catch {
      _ => panic()
    },
    Map::from_array([(name("total") catch { _ => panic() }, int)]),
  )
  assert_eq(show_type(ctx, extensible), "{ r | total : Int }")
  let constrained = @ir.Type::Variable(
    {
      ..plain(),
      constraints: Map::from_array([("typeclass", @ir.Data::Text("comparable"))]),
    },
    name("k") catch {
      _ => panic()
    },
  )
  assert_eq(show_type(ctx, constrained), "comparableK")
}

///|
test "tuples of more than three elements are refused" {
  let ctx = ctx_for()
  let int = ref_type("morphir/SDK:basics#int")
  assert_eq(
    show_type(ctx, @ir.Type::Tuple(plain(), [int, int])),
    "( Int, Int )",
  )
  let code = try {
    ignore(
      lower_type(
        ctx,
        @ir.Type::Tuple(plain(), [int, int, int, int]),
        "acme/app:orders#t",
      ),
    )
    ""
  } catch {
    Refused(problem) => problem.code + " " + problem.node_path
    _ => "other"
  }
  assert_eq(code, "elm.tuple_arity acme/app:orders#t")
}

///|
test "custom types are opaque when constructors are private" {
  let ctx = ctx_for()
  let int = ref_type("morphir/SDK:basics#int")
  let name = fn(s) { @ir.Name::parse(s) catch { _ => panic() } }
  let constructors : @ir.Constructors = Map::from_array([
    (name("paid"), [(name("amount"), int)]),
    (name("open"), []),
  ])
  let open_type = @ir.TypeDefinition::CustomTypeDefinition([name("a")], {
    access: Public,
    value: constructors,
  })
  let (declaration, expose) = lower_type_definition(
    ctx,
    name("status"),
    Some("Order status."),
    open_type,
    "s",
  )
  let printed = @printer.print_declaration(node(declaration))
  assert_true(printed.contains("type Status a\n    = Paid Int\n    | Open"))
  assert_true(printed.has_prefix("{-| Order status.\n-}"))
  assert_eq(expose, Some(TypeExpose({ name: "Status", open: Some(zero), })))
  let hidden = @ir.TypeDefinition::CustomTypeDefinition([], {
    access: Private,
    value: constructors,
  })
  assert_eq(
    lower_type_definition(ctx, name("status"), None, hidden, "s").1,
    Some(TypeOrAliasExpose("Status")),
  )
}

///|
test "derived and incomplete type definitions are refused" {
  let ctx = ctx_for()
  let name = fn(s) { @ir.Name::parse(s) catch { _ => panic() } }
  let int = ref_type("morphir/SDK:basics#int")
  let derived : @ir.TypeSpecification = {
    annotations: [],
    body: DerivedTypeSpecification([], {
      base_type: int,
      from_base_type: @ir.FQName::parse("acme/app:orders#from-int") catch {
        _ => panic()
      },
      to_base_type: @ir.FQName::parse("acme/app:orders#to-int") catch {
        _ => panic()
      },
    }),
  }
  let code = try {
    ignore(lower_type_specification(ctx, name("id"), None, derived, "d"))
    ""
  } catch {
    Refused(problem) => problem.code
    _ => "other"
  }
  assert_eq(code, "elm.derived_type")
  let incomplete = @ir.TypeDefinition::IncompleteTypeDefinition([], Draft, None)
  let code2 = try {
    ignore(lower_type_definition(ctx, name("id"), None, incomplete, "d"))
    ""
  } catch {
    Refused(problem) => problem.code
    _ => "other"
  }
  assert_eq(code2, "elm.placeholder")
}
