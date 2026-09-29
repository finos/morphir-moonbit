///|
test "zero divisors raise recoverable SDK errors" {
  let n = from_int(7)
  let z = from_int(0)
  for
    op in [
      fn() raise { divide(n, z) },
      fn() raise { remainder_by(z, n) },
      fn() raise { mod_by(z, n) },
    ] {
    let failed = try {
      ignore(op())
      false
    } catch {
      @sdk.DivisionByZero => true
      _ => false
    }
    assert_true(failed)
  }
}

///|
test "checked conversion and exact IEEE integer decoding" {
  assert_eq(to_int(parse("2147483648")), None)
  assert_eq(to_int64(parse("9223372036854775808")), None)
  assert_eq(to_string(from_float_truncated(-3.9)), "-3")
  assert_eq(
    to_string(from_float_truncated(9007199254740992.0)),
    "9007199254740992",
  )
  assert_eq(
    to_string(from_float_truncated(1.0e30)),
    "1000000000000000019884624838656",
  )
  assert_eq(from_string("1e3"), None)
  assert_eq(from_string(""), None)
  assert_eq(
    to_string(power(from_int(2), from_int(100))),
    "1267650600228229401496703205376",
  )
}

///|
// Oracle: Python integer arithmetic; truncation explicitly computed from absolute values.
test "exact arithmetic and all signed divisor combinations" {
  assert_eq(to_string(divide(parse("0"), parse("3"))), "0")
  assert_eq(to_string(remainder_by(parse("3"), parse("0"))), "0")
  assert_eq(to_string(mod_by(parse("3"), parse("0"))), "0")
  assert_eq(to_string(divide(parse("0"), parse("-3"))), "0")
  assert_eq(to_string(remainder_by(parse("-3"), parse("0"))), "0")
  assert_eq(to_string(mod_by(parse("-3"), parse("0"))), "0")
  assert_eq(to_string(divide(parse("0"), parse("1"))), "0")
  assert_eq(to_string(remainder_by(parse("1"), parse("0"))), "0")
  assert_eq(to_string(mod_by(parse("1"), parse("0"))), "0")
  assert_eq(to_string(divide(parse("0"), parse("-1"))), "0")
  assert_eq(to_string(remainder_by(parse("-1"), parse("0"))), "0")
  assert_eq(to_string(mod_by(parse("-1"), parse("0"))), "0")
  assert_eq(to_string(divide(parse("0"), parse("18446744073709551617"))), "0")
  assert_eq(
    to_string(remainder_by(parse("18446744073709551617"), parse("0"))),
    "0",
  )
  assert_eq(to_string(mod_by(parse("18446744073709551617"), parse("0"))), "0")
  assert_eq(to_string(divide(parse("7"), parse("3"))), "2")
  assert_eq(to_string(remainder_by(parse("3"), parse("7"))), "1")
  assert_eq(to_string(mod_by(parse("3"), parse("7"))), "1")
  assert_eq(to_string(divide(parse("7"), parse("-3"))), "-2")
  assert_eq(to_string(remainder_by(parse("-3"), parse("7"))), "1")
  assert_eq(to_string(mod_by(parse("-3"), parse("7"))), "-2")
  assert_eq(to_string(divide(parse("7"), parse("1"))), "7")
  assert_eq(to_string(remainder_by(parse("1"), parse("7"))), "0")
  assert_eq(to_string(mod_by(parse("1"), parse("7"))), "0")
  assert_eq(to_string(divide(parse("7"), parse("-1"))), "-7")
  assert_eq(to_string(remainder_by(parse("-1"), parse("7"))), "0")
  assert_eq(to_string(mod_by(parse("-1"), parse("7"))), "0")
  assert_eq(to_string(divide(parse("7"), parse("18446744073709551617"))), "0")
  assert_eq(
    to_string(remainder_by(parse("18446744073709551617"), parse("7"))),
    "7",
  )
  assert_eq(to_string(mod_by(parse("18446744073709551617"), parse("7"))), "7")
  assert_eq(to_string(divide(parse("-7"), parse("3"))), "-2")
  assert_eq(to_string(remainder_by(parse("3"), parse("-7"))), "-1")
  assert_eq(to_string(mod_by(parse("3"), parse("-7"))), "2")
  assert_eq(to_string(divide(parse("-7"), parse("-3"))), "2")
  assert_eq(to_string(remainder_by(parse("-3"), parse("-7"))), "-1")
  assert_eq(to_string(mod_by(parse("-3"), parse("-7"))), "-1")
  assert_eq(to_string(divide(parse("-7"), parse("1"))), "-7")
  assert_eq(to_string(remainder_by(parse("1"), parse("-7"))), "0")
  assert_eq(to_string(mod_by(parse("1"), parse("-7"))), "0")
  assert_eq(to_string(divide(parse("-7"), parse("-1"))), "7")
  assert_eq(to_string(remainder_by(parse("-1"), parse("-7"))), "0")
  assert_eq(to_string(mod_by(parse("-1"), parse("-7"))), "0")
  assert_eq(to_string(divide(parse("-7"), parse("18446744073709551617"))), "0")
  assert_eq(
    to_string(remainder_by(parse("18446744073709551617"), parse("-7"))),
    "-7",
  )
  assert_eq(
    to_string(mod_by(parse("18446744073709551617"), parse("-7"))),
    "18446744073709551610",
  )
  assert_eq(
    to_string(divide(parse("1208925819614629174706179"), parse("3"))),
    "402975273204876391568726",
  )
  assert_eq(
    to_string(remainder_by(parse("3"), parse("1208925819614629174706179"))),
    "1",
  )
  assert_eq(
    to_string(mod_by(parse("3"), parse("1208925819614629174706179"))),
    "1",
  )
  assert_eq(
    to_string(divide(parse("1208925819614629174706179"), parse("-3"))),
    "-402975273204876391568726",
  )
  assert_eq(
    to_string(remainder_by(parse("-3"), parse("1208925819614629174706179"))),
    "1",
  )
  assert_eq(
    to_string(mod_by(parse("-3"), parse("1208925819614629174706179"))),
    "-2",
  )
  assert_eq(
    to_string(divide(parse("1208925819614629174706179"), parse("1"))),
    "1208925819614629174706179",
  )
  assert_eq(
    to_string(remainder_by(parse("1"), parse("1208925819614629174706179"))),
    "0",
  )
  assert_eq(
    to_string(mod_by(parse("1"), parse("1208925819614629174706179"))),
    "0",
  )
  assert_eq(
    to_string(divide(parse("1208925819614629174706179"), parse("-1"))),
    "-1208925819614629174706179",
  )
  assert_eq(
    to_string(remainder_by(parse("-1"), parse("1208925819614629174706179"))),
    "0",
  )
  assert_eq(
    to_string(mod_by(parse("-1"), parse("1208925819614629174706179"))),
    "0",
  )
  assert_eq(
    to_string(
      divide(parse("1208925819614629174706179"), parse("18446744073709551617")),
    ),
    "65535",
  )
  assert_eq(
    to_string(
      remainder_by(
        parse("18446744073709551617"),
        parse("1208925819614629174706179"),
      ),
    ),
    "18446744073709486084",
  )
  assert_eq(
    to_string(
      mod_by(parse("18446744073709551617"), parse("1208925819614629174706179")),
    ),
    "18446744073709486084",
  )
  assert_eq(
    to_string(divide(parse("-1208925819614629174706179"), parse("3"))),
    "-402975273204876391568726",
  )
  assert_eq(
    to_string(remainder_by(parse("3"), parse("-1208925819614629174706179"))),
    "-1",
  )
  assert_eq(
    to_string(mod_by(parse("3"), parse("-1208925819614629174706179"))),
    "2",
  )
  assert_eq(
    to_string(divide(parse("-1208925819614629174706179"), parse("-3"))),
    "402975273204876391568726",
  )
  assert_eq(
    to_string(remainder_by(parse("-3"), parse("-1208925819614629174706179"))),
    "-1",
  )
  assert_eq(
    to_string(mod_by(parse("-3"), parse("-1208925819614629174706179"))),
    "-1",
  )
  assert_eq(
    to_string(divide(parse("-1208925819614629174706179"), parse("1"))),
    "-1208925819614629174706179",
  )
  assert_eq(
    to_string(remainder_by(parse("1"), parse("-1208925819614629174706179"))),
    "0",
  )
  assert_eq(
    to_string(mod_by(parse("1"), parse("-1208925819614629174706179"))),
    "0",
  )
  assert_eq(
    to_string(divide(parse("-1208925819614629174706179"), parse("-1"))),
    "1208925819614629174706179",
  )
  assert_eq(
    to_string(remainder_by(parse("-1"), parse("-1208925819614629174706179"))),
    "0",
  )
  assert_eq(
    to_string(mod_by(parse("-1"), parse("-1208925819614629174706179"))),
    "0",
  )
  assert_eq(
    to_string(
      divide(parse("-1208925819614629174706179"), parse("18446744073709551617")),
    ),
    "-65535",
  )
  assert_eq(
    to_string(
      remainder_by(
        parse("18446744073709551617"),
        parse("-1208925819614629174706179"),
      ),
    ),
    "-18446744073709486084",
  )
  assert_eq(
    to_string(
      mod_by(parse("18446744073709551617"), parse("-1208925819614629174706179")),
    ),
    "65533",
  )
}
