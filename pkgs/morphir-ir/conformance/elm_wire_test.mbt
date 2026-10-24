// Elm codecs are the authority for v1-v3 output, including discrepancies with JSON schemas.

///|
test "Elm v1 documented values use a tuple and missing docs default to empty" {
  let literal = @wire.parse("[\"string_literal\",\"value\"]")
  let wrapped = @wire.parse("[\"A doc\",[\"string_literal\",\"value\"]]")
  assert_eq(
    @v1.write_documented(
      @v1.read_documented(wrapped, @v1.read_literal),
      @v1.write_literal,
    ),
    wrapped,
  )
  assert_eq(
    @v1.write_documented(
      @v1.read_documented(literal, @v1.read_literal),
      @v1.write_literal,
    ),
    @wire.parse("[\"\",[\"string_literal\",\"value\"]]"),
  )
}

///|
test "Elm v2 literals are capitalized inside lowercase value tags" {
  let text = "[\"literal\",{},[\"StringLiteral\",\"value\"]]"
  assert_eq(
    @v2.write_value(
      @v2.read_value(@wire.parse(text), read_unit, read_unit),
      write_unit,
      write_unit,
    ),
    @wire.parse(text),
  )
  let wrapped = @wire.parse(
    "{\"doc\":\"\",\"value\":[\"StringLiteral\",\"value\"]}",
  )
  assert_eq(
    @v2.write_documented(
      @v2.read_documented(
        @wire.parse("[\"StringLiteral\",\"value\"]"),
        @v2.read_literal,
      ),
      @v2.write_literal,
    ),
    wrapped,
  )
}

///|
test "Elm v3 accepts undocumented values and always writes a string doc" {
  let raw = @wire.parse("[\"StringLiteral\",\"value\"]")
  assert_eq(
    @v3.write_documented(
      @v3.read_documented(raw, @v3.read_literal),
      @v3.write_literal,
    ),
    @wire.parse("{\"doc\":\"\",\"value\":[\"StringLiteral\",\"value\"]}"),
  )
  let module_spec = @v3.read_module_specification(
    @wire.parse("{\"types\":[],\"values\":[]}"),
    read_unit,
  )
  assert_eq(
    @v3.write_module_specification(module_spec, write_unit),
    @wire.parse("{\"types\":[],\"values\":[],\"doc\":null}"),
  )
}

///|
test "Elm v1 derived specifications retain the encoder's capitalized tag" {
  let text = "[\"DerivedTypeSpecification\",[],{\"baseType\":[\"unit\",{}],\"fromBaseType\":[[[\"example\"]],[[\"main\"]],[\"from\"]],\"toBaseType\":[[[\"example\"]],[[\"main\"]],[\"to\"]]}]"
  let model = @v1.read_type_specification(@wire.parse(text), read_unit)
  assert_eq(@v1.write_type_specification(model, write_unit), @wire.parse(text))
}

///|
test "Elm Dict order uses legacy word lists, including initialisms and prefixes" {
  let input = "[\"record\",{},[[[\"z\"],[\"unit\",{}]],[[\"a\",\"b\"],[\"unit\",{}]],[[\"a\"],[\"unit\",{}]],[[\"s\",\"d\",\"k\"],[\"unit\",{}]],[[\"b\"],[\"unit\",{}]]]]"
  let expected = "[\"record\",{},[[[\"a\"],[\"unit\",{}]],[[\"a\",\"b\"],[\"unit\",{}]],[[\"b\"],[\"unit\",{}]],[[\"s\",\"d\",\"k\"],[\"unit\",{}]],[[\"z\"],[\"unit\",{}]]]]"
  assert_eq(
    @v1.write_value(
      @v1.read_value(@wire.parse(input), read_unit, read_unit),
      write_unit,
      write_unit,
    ),
    @wire.parse(expected),
  )
}

///|
test "v1 downgrade refuses module docs which its Elm encoder cannot carry" {
  assert_eq(
    downgrade_diagnostic(greeting(), 1U),
    "unsupported_module_documentation",
  )
}
