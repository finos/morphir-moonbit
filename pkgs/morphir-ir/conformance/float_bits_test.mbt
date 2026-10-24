///|
test "float JSON literal codecs preserve negative zero and subnormal bits" {
  for value in [-0.0, 0.0, 5.0e-324, -5.0e-324, 1.2345678901234567] {
    let json = @v4.write_literal(@current.Literal::FloatLiteral(value))
    guard @v4.read_literal(@wire.parse(json.stringify()))
      is FloatLiteral(restored) else {
      fail("Float literal")
    }
    assert_eq(restored.reinterpret_as_uint64(), value.reinterpret_as_uint64())
    let historical = @wire.write_float(value)
    assert_eq(
      @wire.float(@wire.parse(historical.stringify())).reinterpret_as_uint64(),
      value.reinterpret_as_uint64(),
    )
  }
}
