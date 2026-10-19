///|
fn scalar_type(text : String) -> @model.Type raise {
  read_type(@core_json.parse(text))
}

///|
test "scalar Union decodes one interpretation and collapses duplicate members" {
  let t = scalar_type(
    "{\"Union\":[\"morphir/SDK:string#string\",\"morphir/SDK:string#string\"]}",
  )
  assert_eq(
    decode_scalar_json("\"ok\"", t, StrictJsonScalars),
    Decoded(StringLiteral("ok")),
  )
  assert_eq(decode_scalar_json("false", t, StrictJsonScalars), Rejected)
}

///|
test "scalar Union treats Int and Float as distinct and supports integral decimal tokens" {
  let t = scalar_type(
    "{\"Union\":[\"morphir/SDK:basics#int\",\"morphir/SDK:basics#float\"]}",
  )
  for text in ["1", "1.0", "1e0"] {
    guard decode_scalar_json(text, t, StrictJsonScalars) is Ambiguous(xs) else {
      fail("numeric ambiguity lost")
    }
    assert_eq(xs.length(), 2)
    assert_true(xs.contains(IntegerLiteral("1")))
    assert_true(xs.contains(FloatLiteral(1.0)))
  }
  assert_eq(
    decode_scalar_json("1", t, IntegerTokenAsInt),
    Decoded(IntegerLiteral("1")),
  )
  assert_eq(
    decode_scalar_json("1.0", t, IntegerTokenAsInt),
    Decoded(IntegerLiteral("1")),
  )
  assert_eq(
    decode_scalar_json("1e0", t, IntegerTokenAsInt),
    Decoded(IntegerLiteral("1")),
  )
}

///|
test "scalar Union unsupported arms prevent a uniqueness claim" {
  let t = scalar_type(
    "{\"Union\":[\"morphir/SDK:string#string\",\"example:opaque#id\"]}",
  )
  assert_eq(
    decode_scalar_json("\"ok\"", t, StrictJsonScalars),
    Unsupported(UnsupportedType),
  )
}

///|
test "scalar Union retains outer refinement obligations and rejects wrong scalar shapes" {
  let t = scalar_type(
    "{\"Union\":{\"attributes\":{\"extensions\":{\"unknown\":true}},\"alternatives\":[\"morphir/SDK:string#string\",\"morphir/SDK:basics#int\"]}}",
  )
  assert_eq(
    decode_scalar_json("\"ok\"", t, StrictJsonScalars),
    Unsupported(UnsupportedRefinement),
  )
  assert_eq(decode_scalar_json("false", t, StrictJsonScalars), Rejected)
}

///|
test "scalar Union checks member refinements and preserves proved numeric ambiguity" {
  let t = scalar_type(
    "{\"Union\":[{\"Reference\":{\"attributes\":{\"extensions\":{\"unknown\":true}},\"fqname\":\"morphir/SDK:basics#int\"}},\"morphir/SDK:string#string\"]}",
  )
  assert_eq(
    decode_scalar_json("1", t, StrictJsonScalars),
    Unsupported(UnsupportedRefinement),
  )
  assert_eq(
    decode_scalar_json("\"ok\"", t, StrictJsonScalars),
    Decoded(StringLiteral("ok")),
  )
  let ambiguous = scalar_type(
    "{\"Union\":[\"morphir/SDK:basics#float\",\"example:opaque#id\",\"morphir/SDK:basics#int\"]}",
  )
  assert_true(
    decode_scalar_json("1", ambiguous, StrictJsonScalars) is Ambiguous(_),
  )
}

///|
test "scalar codec refuses unknown profiles and numeric precision outside its bound" {
  try ScalarProfile::parse("guess-first") catch {
    @wire.Invalid(code, _) => assert_eq(code, "unsupported_scalar_profile")
  } noraise {
    _ => fail("unknown profile accepted")
  }
  let t = scalar_type("\"morphir/SDK:basics#float\"")
  for text in ["9007199254740993", "1e-999"] {
    assert_eq(
      decode_scalar_json(text, t, StrictJsonScalars),
      Unsupported(NumericLimit),
    )
  }
  let arm = scalar_type("\"morphir/SDK:string#string\"")
  let big : @model.Type = Union(Default::default(), Array::make(300, arm))
  assert_eq(
    decode_scalar_json("\"ok\"", big, StrictJsonScalars),
    Unsupported(WorkLimit),
  )
}

///|
test "scalar decoder resolves visible alias overlap and retains alias occurrence obligations" {
  let file = read(
    "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"example\",\"def\":{\"modules\":{\"types\":{\"Public\":{\"types\":{\"label\":{\"Public\":{\"value\":{\"TypeAliasDefinition\":{\"typeParams\":[],\"typeExp\":\"morphir/SDK:string#string\"}}}},\"cycle\":{\"Public\":{\"value\":{\"TypeAliasDefinition\":{\"typeParams\":[],\"typeExp\":\"example:types#cycle\"}}}}},\"values\":{}}}}}}}}",
  )
  let decoder = ScalarDecoder::from(file, StrictJsonScalars)
  let overlap = scalar_type(
    "{\"Union\":[\"morphir/SDK:string#string\",\"example:types#label\"]}",
  )
  assert_eq(decoder.decode("\"ok\"", overlap), Decoded(StringLiteral("ok")))
  assert_eq(
    decoder.decode("1", scalar_type("\"example:types#cycle\"")),
    Unsupported(CyclicAlias),
  )
  let refined = scalar_type(
    "{\"Reference\":{\"attributes\":{\"extensions\":{\"unknown\":true}},\"fqname\":\"example:types#label\"}}",
  )
  assert_eq(
    decoder.decode("\"ok\"", refined),
    Unsupported(UnsupportedRefinement),
  )
}

///|
test "scalar Union textual provenance is descriptive on outer and member types" {
  for
    text in [
      "{\"Union\":{\"attributes\":{\"extensions\":{\"example/union:provenance#note\":\"note\"}},\"alternatives\":[\"morphir/SDK:string#string\",\"morphir/SDK:basics#int\"]}}",
      "{\"Union\":[{\"Reference\":{\"attributes\":{\"extensions\":{\"example/union:provenance#note\":\"note\"}},\"fqname\":\"morphir/SDK:string#string\"}},\"morphir/SDK:basics#int\"]}",
    ] {
    assert_eq(
      decode_scalar_json("\"ok\"", scalar_type(text), StrictJsonScalars),
      Decoded(StringLiteral("ok")),
    )
  }
  let invalid = scalar_type(
    "{\"Union\":{\"attributes\":{\"extensions\":{\"example/union:provenance#note\":true}},\"alternatives\":[\"morphir/SDK:string#string\",\"morphir/SDK:basics#int\"]}}",
  )
  assert_eq(
    decode_scalar_json("\"ok\"", invalid, StrictJsonScalars),
    Unsupported(UnsupportedRefinement),
  )
}
