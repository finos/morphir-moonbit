///|
fn fq(text : String) -> @ir.FQName {
  @ir.FQName::parse(text) catch {
    _ => panic()
  }
}

///|
test "built-in table maps elm/core semantics and leaves the rest" {
  let mapping = Mapping::builtin()
  assert_eq(mapping.lookup(fq("morphir/SDK:basics#add")), Some(Operator("+")))
  assert_eq(mapping.lookup(fq("morphir/SDK:list#cons")), Some(Operator("::")))
  assert_eq(
    mapping.lookup(fq("morphir/SDK:list#map")),
    Some(Function("List.map", None)),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:basics#max")),
    Some(Function("max", None)),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:dict#insert")),
    Some(Function("Dict.insert", Some("Dict"))),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:maybe#just")),
    Some(Function("Just", None)),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:basics#int")),
    Some(Type("Int", None)),
  )
  // Decimal semantics are not elm/core, so the reference stays qualified.
  assert_eq(mapping.lookup(fq("morphir/SDK:decimal#add")), None)
}

///|
test "overrides replace, extend and remove entries" {
  let mapping = Mapping::builtin().with_overrides(
    Map::from_array([
      ("morphir/SDK:basics#max", Removed),
      ("acme/app:money#add", Function("Money.plus", Some("Money"))),
      ("morphir/SDK:list#map", Function("Array.map", Some("Array"))),
    ]),
  )
  assert_eq(mapping.lookup(fq("morphir/SDK:basics#max")), None)
  assert_eq(
    mapping.lookup(fq("acme/app:money#add")),
    Some(Function("Money.plus", Some("Money"))),
  )
  assert_eq(
    mapping.lookup(fq("morphir/SDK:list#map")),
    Some(Function("Array.map", Some("Array"))),
  )
  assert_eq(
    Mapping::builtin().lookup(fq("morphir/SDK:basics#max")),
    Some(Function("max", None)),
  )
}

///|
test "mapping entries parse from JSON" {
  assert_eq(
    parse_mapping_entry(
      "morphir/SDK:basics#add",
      Json::object(Map::from_array([("operator", Json::string("+"))])),
    ),
    Operator("+"),
  )
  assert_eq(
    parse_mapping_entry(
      "morphir/SDK:decimal#decimal",
      Json::object(
        Map::from_array([
          ("type", Json::string("Decimal.Decimal")),
          ("import", Json::string("MyCo.Decimal as Decimal")),
        ]),
      ),
    ),
    Type("Decimal.Decimal", Some("MyCo.Decimal as Decimal")),
  )
  assert_eq(
    parse_mapping_entry("morphir/SDK:basics#max", Json::object(Map([]))),
    Removed,
  )
  for
    bad in [
      (
        "not a name",
        Json::object(Map::from_array([("function", Json::string("f"))])),
      ),
      (
        "a:b#c",
        Json::object(
          Map::from_array([
            ("function", Json::string("f")),
            ("type", Json::string("T")),
          ]),
        ),
      ),
      (
        "a:b#c",
        Json::object(Map::from_array([("colour", Json::string("red"))])),
      ),
      ("a:b#c", Json::string("f")),
    ] {
    let code = try {
      ignore(parse_mapping_entry(bad.0, bad.1))
      ""
    } catch {
      Refused(problem) => problem.code
      _ => "other"
    }
    assert_eq(code, "elm.invalid_mapping")
  }
}
