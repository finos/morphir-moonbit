///|
test "nested edits preserve siblings and do not mutate the prior document" {
  let initial = "[{\"products\":[[{\"price\":12.5},\"2\"]],\"status\":{\"constructor\":\"demo:main#pending\",\"arguments\":[]}},20]"
  let changed = @arguments.edit(
    initial,
    Scalar(
      [Index(0), Field("products"), Index(0), Index(0), Field("price")],
      "float",
      "15.00",
    ),
  )
  let data = @wire.array(@wire.parse(changed))
  assert_eq(data[1], Json::number(20))
  assert_eq(
    @wire.field(data[0], "status"),
    @wire.field(@wire.array(@wire.parse(initial))[0], "status"),
  )
  assert_eq(
    @wire.number_text(
      @wire.field(
        @wire.array(@wire.array(@wire.field(data[0], "products"))[0])[0],
        "price",
      ),
    ),
    "15.00",
  )
  let added = @arguments.edit(
    changed,
    Append(
      [Index(0), Field("products")],
      Json::array([
        Json::object(Map([("price", Json::number(5))])),
        Json::string("1"),
      ]),
    ),
  )
  let removed = @arguments.edit(added, Remove([Index(0), Field("products")], 0))
  assert_eq(
    @wire.array(@wire.field(@wire.array(@wire.parse(removed))[0], "products")).length(),
    1,
  )
  assert_eq(
    @wire.array(@wire.field(@wire.array(@wire.parse(initial))[0], "products")).length(),
    1,
  )
}

///|
test "numeric drafts and exact integer text survive JSON editing round trips" {
  let draft = @arguments.edit("[0,\"0\"]", Scalar([Index(0)], "float", "1e"))
  assert_eq(draft, "[\"1e\",\"0\"]")
  let completed = @arguments.edit(draft, Scalar([Index(0)], "float", "1e+23"))
  let exact = @arguments.edit(
    completed,
    Scalar([Index(1)], "int", "9007199254740993123456789"),
  )
  let values = @wire.array(@wire.parse(exact))
  assert_eq(@arguments.scalar_text(values[0]), "1e+23")
  assert_eq(@arguments.scalar_text(values[1]), "9007199254740993123456789")
}

///|
fn float_profile() -> Json {
  @wire.obj([
    (
      "inputs",
      Json::array([
        @wire.obj([
          ("label", Json::string("price")),
          (
            "schema",
            @wire.obj([
              ("kind", Json::string("float")),
              ("label", Json::string("Float")),
            ]),
          ),
        ]),
      ]),
    ),
  ])
}

///|
test "fields preserve incompatible JSON instead of replacing it with defaults" {
  let profile = float_profile()
  assert_eq(@arguments.form_error(profile, "[\"1e\"]"), None)
  assert_true(@arguments.form_error(profile, "[true]") is Some(_))
  assert_true(@arguments.form_error(profile, "[") is Some(_))
  assert_true(@arguments.form_error(profile, "[0,1]") is Some(_))
  let error = try {
    ignore(@arguments.edit("[0]", Scalar([Index(4)], "float", "2")))
    false
  } catch {
    _ => true
  }
  assert_true(error)
  assert_eq(
    @arguments.edit("[", Set([], Json::array([Json::number(0)]))),
    "[0]",
  )
}

///|
test "large collections fall back to JSON without discarding values" {
  let profile = @wire.obj([
    (
      "inputs",
      Json::array([
        @wire.obj([
          ("label", Json::string("items")),
          (
            "schema",
            @wire.obj([
              ("kind", Json::string("list")),
              ("label", Json::string("List Float")),
              (
                "item",
                @wire.obj([
                  ("kind", Json::string("float")),
                  ("label", Json::string("Float")),
                ]),
              ),
            ]),
          ),
        ]),
      ]),
    ),
  ])
  let document = Json::array([Json::array(Array::make(250, Json::number(1)))]).stringify()
  assert_true(
    @arguments.form_error(profile, document).unwrap().contains("too large"),
  )
  assert_eq(@wire.array(@wire.array(@wire.parse(document))[0]).length(), 250)
}
