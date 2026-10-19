///|
fn union_type() -> @ir.Type raise {
  Union(Default::default(), [
    Reference(
      Default::default(),
      @ir.FQName::parse("morphir/SDK:string#string"),
      [],
    ),
    Reference(Default::default(), @ir.FQName::parse("morphir/SDK:basics#int"), []),
  ])
}

///|
test "Union inferred type is refused before direct native literal evaluation" {
  let value : @ir.Value = Literal(
    { ..attrs(), inferred_type: Some(union_type()), },
    IntegerLiteral("1"),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  try @backend.evaluate_in(runtime, value) catch {
    @scheme.Unsupported(_) => ()
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union native literal evaluation was accepted")
  }
}

///|
test "Union pattern annotation is refused by direct emission" {
  let p : @ir.Pattern = WildcardPattern({
    ..attrs(),
    inferred_type: Some(union_type()),
  })
  let value : @ir.Value = Lambda(attrs(), p, int("1"))
  try @backend.emit_expression(value) catch {
    @scheme.Unsupported(_) => ()
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union pattern was erased")
  }
}

///|
test "Union signature is refused before selected aliases are pruned" {
  let file = file(ExpressionBody([], union_type(), int("1")))
  try @backend.selected_file(file, @ir.FQName::parse("test:main#main")) catch {
    @backend.SelectedReferenceInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union selected signature was accepted")
  }
}

///|
test "Union registered native entry is refused before host code runs" {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let entry = @ir.FQName::parse("test:main#main")
  let called : Ref[Bool] = { val: false, }
  @backend.register_native(runtime, entry, fn(_rt, _args) raise {
    called.val = true
    @scheme.integer("1")
  })
  let file = file(
    NativeBody([], union_type(), { hint: Arithmetic, description: None, }),
  )
  try @backend.run_file_in(runtime, file, entry, []) catch {
    @scheme.Unsupported(_) => ()
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union native entry was accepted")
  }
  assert_false(called.val)
  try @backend.link_file(runtime, file) catch {
    @scheme.Unsupported(_) => ()
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("Union file linked")
  }
}

///|
test "Union aliases are checked only when reachable by selected definitions" {
  let initial = file(ExpressionBody([], Unit(Default::default()), int("1")))
  guard initial.distribution is Library(p, deps, d) else {
    fail("not a library")
  }
  let module_name = @ir.Path::parse("main")
  let m = d.modules[module_name]
  let union_ref : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("test:main#hidden"),
    [],
  )
  let types : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.TypeDefinition]],
  ] = Map([
    (
      name("hidden"),
      {
        access: Private,
        value: {
          doc: None,
          value: @ir.TypeDefinition::TypeAliasDefinition([], union_type()),
        },
      },
    ),
  ])
  let with_types : @ir.PackageDefinition = {
    modules: Map([(module_name, { ..m, value: { ..m.value, types, }, })]),
  }
  let unused = @ir.IRFile::new(Library(p, deps, with_types))
  ignore(@backend.emit_selected(unused, @ir.FQName::parse("test:main#main")))
  let values = m.value.values.copy()
  values[name("main")] = {
    access: Public,
    value: { doc: None, value: ExpressionBody([], union_ref, int("1")), },
  }
  let used = @ir.IRFile::new(
    Library(p, deps, {
      modules: Map([
        (module_name, { ..m, value: { ..m.value, types, values, }, }),
      ]),
    }),
  )
  try @backend.selected_file(used, @ir.FQName::parse("test:main#main")) catch {
    @backend.SelectedReferenceInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    e => fail("wrong error: " + e.to_string())
  } noraise {
    _ => fail("reachable alias was erased")
  }
}
