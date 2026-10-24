///|
test "v4 ordered parameters survive pair arrays and canonical JSON" {
  let parameters = @v4.read_inputs(
    @wire.parse(
      "[[\"z\",\"morphir/SDK:basics#int\"],[\"a\",\"morphir/SDK:basics#bool\"]]",
    ),
  )
  assert_eq(parameters.map(p => p.0.to_canonical()), ["z", "a"])
  let written = @v4.write_inputs(parameters)
  assert_true(written is Array(_))
  assert_eq(@v4.read_inputs(@wire.parse(written.stringify())), parameters)
  let object = @v4.read_inputs(
    @wire.parse(
      "{\"z\":\"morphir/SDK:basics#int\",\"a\":\"morphir/SDK:basics#bool\"}",
    ),
  )
  assert_eq(object.map(p => p.0.to_canonical()), ["a", "z"])
  assert_true(@v4.write_inputs(object) is Object(_))
}
