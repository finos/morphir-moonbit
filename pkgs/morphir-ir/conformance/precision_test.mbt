///|
test "integer and decimal text survives all target runtimes" {
  for integer in ["18446744073709551616000001", "-9223372036854775809"] {
    let lower = "[\"whole_number_literal\"," + integer + "]"
    let upper = "[\"WholeNumberLiteral\"," + integer + "]"
    assert_eq(
      @v1.write_literal(@v1.read_literal(@wire.parse(lower))).stringify(),
      lower,
    )
    assert_eq(
      @v2.write_literal(@v2.read_literal(@wire.parse(upper))).stringify(),
      upper,
    )
    assert_eq(
      @v3.write_literal(@v3.read_literal(@wire.parse(upper))).stringify(),
      upper,
    )
    let v4 = "{\"IntegerLiteral\":" + integer + "}"
    assert_eq(
      @v4.write_literal(@v4.read_literal(@wire.parse(v4))).stringify(),
      v4,
    )
  }
  let decimal = "{\"DecimalLiteral\":\"+0010.5000e-100\"}"
  assert_eq(
    @v4.write_literal(@v4.read_literal(@wire.parse(decimal))).stringify(),
    decimal,
  )
  let document = "{\"DocumentLiteral\":{\"huge\":18446744073709551616000001,\"tiny\":1e-400}}"
  assert_eq(
    @v4.write_literal(@v4.read_literal(@wire.parse(document))).stringify(),
    document,
  )
}

///|
test "duplicate raw and normalized keys are rejected" {
  for
    text in [
      "{\"Record\":{\"fields\":{\"x\":1,\"x\":2}}}", "{\"Record\":{\"fields\":[[\"SDK\",1],[[\"s\",\"d\",\"k\"],2]]}}",
      "{\"Record\":{\"fields\":{\"x\":1,\"\\u0078\":2}}}",
    ] {
    let result = try {
      ignore(@v4.read_value(@wire.parse(text)))
      "accepted"
    } catch {
      e => @wire.diagnostic(e)
    }
    assert_eq(result, "duplicate_member")
  }
}

///|
test "JSON parser rejects truncation, trailing tokens and trailing commas" {
  for
    text in [
      "", "[", "{", "[1,]", "{\"x\":1,}", "true false", "01", "\"unterminated", "{\"x\":}",
    ] {
    let result = try {
      ignore(@wire.parse(text))
      "accepted"
    } catch {
      e => @wire.diagnostic(e)
    }
    assert_eq(result, "invalid_json")
  }
}
