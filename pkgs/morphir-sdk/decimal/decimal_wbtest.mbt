///|
// Oracle: chain-partners/elm-bignum 1.0.1 Decimal.elm via Morphir.SDK.Decimal
// at bc99af69a8b24d391311fae3822a87eafef3c334.
test "exact parse, arithmetic and normalization" {
  let a = from_string("1208925819614629174706179").unwrap()
  let b = from_string("0.001200").unwrap()
  assert_eq(to_string(a), "1208925819614629174706179")
  assert_eq(to_string(b), "0.0012")
  assert_eq(to_string(add(b, b)), "0.0024")
  assert_eq(to_string(mul(b, b)), "0.00000144")
  assert_eq(to_string(sub(b, b)), "0")
  assert_eq(to_string(shift_decimal_right(4, b)), "12")
  assert_eq(to_string(shift_decimal_left(2, b)), "0.000012")
  assert_eq(from_string("1."), None)
  assert_eq(from_string("+1"), None)
  assert_eq(to_string(from_string("1.2e3").unwrap()), "1200")
}

///|
test "half even rounding and division policies" {
  assert_eq(to_string(round(from_string("2.5").unwrap())), "2")
  assert_eq(to_string(round(from_string("3.5").unwrap())), "4")
  assert_eq(to_string(round(from_string("-2.5").unwrap())), "-2")
  assert_eq(to_string(round(from_string("-3.5").unwrap())), "-4")
  assert_eq(to_string(truncate(from_string("-3.9").unwrap())), "-3")
  assert_eq(div(one(), zero()), None)
  assert_eq(
    to_string(div(one(), from_int(@integer.from_int(3))).unwrap()),
    "0.33333333333333333333333333333333",
  )
  assert_eq(to_string(div_with_default(one(), one(), zero())), "1")
}

///|
test "nonfinite Float is an explicit SDK conversion error" {
  let rejected = try {
    ignore(from_float(1.0 / 0.0))
    false
  } catch {
    @sdk.InvalidNumber(_) => true
    _ => false
  }
  assert_true(rejected)
}
