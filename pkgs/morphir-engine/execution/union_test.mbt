///|
test "selected Scheme planners refuse a reachable private Union alias helper" {
  let union : @ir.Type = Union(Default::default(), [
    selected_int(),
    selected_int(),
  ])
  let hidden : @ir.Type = Reference(
    Default::default(),
    @ir.FQName::parse("selected:main#hidden"),
    [],
  )
  let unit = selected_unit(
    ExpressionBody(
      [],
      hidden,
      @ir.Value::Literal(Default::default(), IntegerLiteral("1")),
    ),
  )
  guard unit.distribution.distribution is Library(_, _, d) else {
    fail("library")
  }
  let m = d.modules[@ir.Path::parse("main")].value
  m.types[@ir.Name::parse("hidden")] = {
    access: Private,
    value: { doc: None, value: TypeAliasDefinition([], union), },
  }
  let helper = m.values[@ir.Name::parse("unused")]
  m.values[@ir.Name::parse("unused")] = { ..helper, access: Private, }
  let answer = m.values[@ir.Name::parse("answer")]
  m.values[@ir.Name::parse("answer")] = {
    ..answer,
    value: {
      ..answer.value,
      value: ExpressionBody(
        [],
        selected_int(),
        Reference(Default::default(), @ir.FQName::parse("selected:main#unused")),
      ),
    },
  }
  try @execution.plan_scheme(unit, selected_suite(), policy=Permissive) catch {
    @execution.AdmissionInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    error => fail("wrong error: " + error.to_string())
  } noraise {
    _ => fail("reachable Union helper planned")
  }
  try
    @execution.plan_scheme_capabilities(
      unit,
      selected_suite(),
      policy=Permissive,
    )
  catch {
    @execution.AdmissionInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    error => fail("wrong error: " + error.to_string())
  } noraise {
    _ => fail("reachable Union helper capability planned")
  }
}

///|
test "selected Scheme permits an unrelated Union declaration and rejects public Union boundaries" {
  let union : @ir.Type = Union(Default::default(), [
    selected_int(),
    selected_int(),
  ])
  let unit = selected_unit(
    ExpressionBody(
      [],
      union,
      @ir.Value::Literal(Default::default(), IntegerLiteral("1")),
    ),
  )
  ignore(
    @execution.plan_scheme_capabilities(
      unit,
      selected_suite(),
      policy=Permissive,
    ),
  )
  selected_definition(unit, [], union)
  try @execution.plan_scheme(unit, selected_suite(), policy=Permissive) catch {
    @execution.AdmissionInvalid(code) =>
      assert_eq(code, "execution.unsupported_type")
    error => fail("wrong error: " + error.to_string())
  } noraise {
    _ => fail("Union boundary planned")
  }
}
