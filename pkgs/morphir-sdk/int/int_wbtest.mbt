///|
// Oracle: Morphir.SDK.Int at bc99af69a8b24d391311fae3822a87eafef3c334.
test "fixed width bounds are checked" {
  assert_eq(to_int8(@integer.from_int(-129)), None)
  assert_eq(
    to_int8(@integer.from_int(-128)).map(from_int8),
    Some(@integer.from_int(-128)),
  )
  assert_eq(
    to_int8(@integer.from_int(127)).map(from_int8),
    Some(@integer.from_int(127)),
  )
  assert_eq(to_int8(@integer.from_int(128)), None)
  assert_eq(to_int16(@integer.from_int(32768)), None)
  assert_eq(to_int32(@integer.from_int64(2147483648L)), None)
  assert_eq(to_int64(@integer.parse("-9223372036854775809")), None)
  assert_eq(
    to_int64(@integer.parse("9223372036854775807")).map(from_int64),
    Some(@integer.parse("9223372036854775807")),
  )
}
