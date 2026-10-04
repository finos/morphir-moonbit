///|
test "typed Ion arguments preserve native exact numbers and rich annotations" {
  let values : Json = [
    { "type": "int", "value": "9007199254740993" },
    { "type": "decimal", "coefficient": "125", "exponent": -1 },
    { "type": "float64", "bits": "9223372036854775808" },
    { "type": "text", "units": [55296, 0] },
    {
      "type": "maybe",
      "case": "just",
      "value": { "type": "int", "value": "9" },
    },
    {
      "type": "custom",
      "owner": "demo:main#state",
      "tag": "demo:main#done",
      "items": [],
    },
    { "type": "unit" },
  ]
  let source = @arguments.convert_inputs(
    Json::null(),
    values.stringify(),
    false,
    true,
    true,
  )
  assert_true(source.contains("9007199254740993"))
  assert_true(source.contains("morphir_value"))
  assert_true(source.contains("morphir_unit"))
  assert_eq(@arguments.ion_arguments(Json::null(), source, true), values)
  assert_eq(
    @arguments.ion_arguments(Json::null(), "[9007199254740993, 12.5]", true),
    [
      { "type": "int", "value": "9007199254740993" },
      { "type": "decimal", "coefficient": "125", "exponent": -1 },
    ],
  )
}

///|
test "Ion parse and unsupported projection errors preserve the original document" {
  for
    source in [
      "[", "1 2", "[timestamp::1]", "[morphir_value::{type:\"text\",units:[65536]}]",
    ] {
    assert_true(
      try {
        ignore(
          @arguments.convert_inputs(Json::null(), source, true, false, true),
        )
        false
      } catch {
        _ => true
      },
    )
  }
  let profile : Json = { "inputs": [{ "schema": { "kind": "int" } }] }
  assert_eq(@arguments.ion_arguments(profile, "[9007199254740993]", false), [
    "9007199254740993",
  ])
  for source in ["[ann::1]", "[2026-10-01T]", "[{a:1,a:2}]"] {
    assert_true(
      try {
        ignore(@arguments.ion_arguments(profile, source, false))
        false
      } catch {
        _ => true
      },
    )
  }
  let invalid = "[{\"type\":\"decimal\",\"coefficient\":\"1\",\"exponent\":\"-\"}]"
  assert_true(
    try {
      ignore(
        @arguments.convert_inputs(Json::null(), invalid, false, true, true),
      )
      false
    } catch {
      _ => true
    },
  )
}
