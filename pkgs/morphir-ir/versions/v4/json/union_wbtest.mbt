///|
test "Union accepts compact syntax and preserves nested duplicate alternatives" {
  let wire = @core_json.parse("{\"Union\":[\"a\",{\"Union\":[\"a\",\"a\"]}]}")
  assert_eq(write_type(read_type(wire)), wire)
}

///|
test "Union expanded empty attributes canonicalize independently of members" {
  let wire = @core_json.parse(
    "{\"Union\":{\"attributes\":{},\"alternatives\":[\"a\",\"b\"]}}",
  )
  assert_eq(
    write_type(read_type(wire)),
    @core_json.parse("{\"Union\":[\"a\",\"b\"]}"),
  )
}

///|
test "Union rejects insufficient authored arity" {
  for wire in ["{\"Union\":[]}", "{\"Union\":[\"a\"]}"] {
    try read_type(@core_json.parse(wire)) catch {
      @wire.Invalid(code, _) => assert_eq(code, "invalid_arity")
      _ => fail("Expected invalid_arity")
    } noraise {
      _ => fail("Expected invalid_arity")
    }
  }
}
