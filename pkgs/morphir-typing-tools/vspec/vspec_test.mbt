///|
test "canonical names follow the migrated spelling" {
  assert_eq(@vspec.canonical_name("map2"), "map-2")
  assert_eq(@vspec.canonical_name("fromInt8"), "from-int-8")
  assert_eq(@vspec.canonical_name("lessThanOrEqual"), "less-than-or-equal")
  assert_eq(@vspec.canonical_name("isNaN"), "is-na-n")
  assert_eq(@vspec.canonical_name("atan2"), "atan-2")
  assert_eq(@vspec.canonical_name("lt"), "lt")
}

///|
test "a vSpec parses into parameters and a result" {
  let (name, params, result) = @vspec.parse_vspec(
    "vSpec \"foldl\"\n [ ( \"f\", tFun [ tVar \"k\", tVar \"v\", tVar \"b\" ] (tVar \"b\") )\n , ( \"z\", tVar \"b\" )\n , ( \"list\", dictType () (tVar \"k\") (tVar \"v\") ) ] (tVar \"b\") -- dict",
  )
  assert_eq(name, "foldl")
  assert_eq(params.map(p => p.0), ["f", "z", "list"])
  guard params[0].1
    is Function(
      _,
      Variable(_, _),
      Function(_, _, Function(_, _, Variable(_, _)))
    ) else {
    fail("tFun is curried")
  }
  guard params[2].1 is Reference(_, dict, [_, _]) else { fail("dict") }
  assert_eq(dict.to_canonical(), "morphir/SDK:dict#dict")
  assert_true(result is Variable(_, _))
}

///|
test "tuples and unknown types" {
  let (_, params, _) = @vspec.parse_vspec(
    "vSpec \"toPolar\" [ ( \"a\", Type.Tuple () [ floatType (), floatType () ] ) ] (floatType ())",
  )
  assert_true(params[0].1 is Tuple(_, [_, _]))
  let failed = try {
    ignore(@vspec.parse_vspec("vSpec \"x\" [] (localDateType ())"))
    ""
  } catch {
    VSpecError(message) => message
  }
  assert_eq(failed, "unknown SDK type localDateType")
}

///|
test "variables carry the type class of their name" {
  let (_, params, _) = @vspec.parse_vspec(
    "vSpec \"compare\" [ ( \"a\", tVar \"comparable\" ), ( \"b\", tVar \"number1\" ), ( \"c\", tVar \"list1\" ) ] (tVar \"a\")",
  )
  guard params[0].1 is Variable(attrs, name) else { fail("variable") }
  assert_eq(name.to_canonical(), "comparable")
  assert_true(attrs.constraints.get("typeclass") is Some(Text("comparable")))
  guard params[1].1 is Variable(attrs1, name1) else { fail("variable") }
  assert_eq(name1.to_canonical(), "number-1")
  assert_true(attrs1.constraints.get("typeclass") is Some(Text("number")))
  guard params[2].1 is Variable(attrs2, _) else { fail("variable") }
  assert_true(attrs2.constraints.get("typeclass") is None)
}
