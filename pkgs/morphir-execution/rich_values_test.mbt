///|
test "rich values preserve exact bits and UTF16 units in every format" {
  let values : Array[@execution.Value] = [
    Decimal(
      @bigint.BigInt::from_string("12345678901234567890123456789012345"),
      -32,
    ),
    Float64(0UL),
    Float64(0x8000000000000000UL),
    Float64(1UL),
    Float64(0x7ff0000000000000UL),
    Float64(0xfff0000000000000UL),
    Float64(0x7ff8000000000042UL),
    Text([0, 0xd800, 0xdc00, 0xdfff]),
    Character([83, 83]),
    Sequence([]),
    Product([Integer(@bigint.BigInt::from_int(7)), Boolean(false)]),
    Record([("quote", Decimal(@bigint.BigInt::from_int(125), -1))]),
    Constructor("pricing:quotes#status", "pricing:quotes#approved", [
      Optional(Some(Outcome(Err(Unit)))),
    ]),
    Optional(None),
    Outcome(Ok(Unit)),
    ModelError("sdk.division_by_zero"),
  ]
  let suite : @execution.Suite = {
    extensions: None,
    calls: [{ id: "rich", entry: "pricing:main#echo", arguments: values, }],
  }
  for format in ["ion-text", "ion-binary", "json"] {
    assert_eq(@execution.Suite::decode(suite.encode(format), format), suite)
  }
}

///|
test "declared types validate empty collections records and constructor ownership" {
  let int : @execution.ValueType = Int
  let record : @execution.ValueType = Record([("quantity", int)])
  @execution.validate_as(Sequence([]), Sequence(int), [])
  @execution.validate_as(
    Record([("quantity", Integer(@bigint.BigInt::from_int(1)))]),
    record,
    [],
  )
  let definitions : Array[@execution.CustomType] = [
    {
      name: "pricing:quotes#status",
      constructors: [{ name: "pricing:quotes#approved", inputs: [Decimal], }],
    },
  ]
  @execution.validate_as(
    Constructor("pricing:quotes#status", "pricing:quotes#approved", [
      Decimal(@bigint.BigInt::from_int(375), -1),
    ]),
    Custom("pricing:quotes#status"),
    definitions,
  )
  let invalids : Array[(@execution.Value, @execution.ValueType)] = [
    (Record([]), record),
    (Record([("quantity", Unit), ("extra", Unit)]), record),
    (
      Record([
        ("quantity", Integer(@bigint.BigInt::from_int(1))),
        ("quantity", Unit),
      ]),
      record,
    ),
    (
      Constructor("other:main#status", "pricing:quotes#approved", []),
      @execution.Custom("pricing:quotes#status"),
    ),
    (
      Constructor("pricing:quotes#status", "pricing:quotes#approved", []),
      Custom("pricing:quotes#status"),
    ),
    (
      Constructor("pricing:quotes#status", "other:main#approved", []),
      Custom("pricing:quotes#status"),
    ),
    (Unit, @execution.Function),
    (ModelError("sdk.division_by_zero"), int),
  ]
  for (value, expected) in invalids {
    assert_true(
      try {
        @execution.validate_as(value, expected, definitions)
        false
      } catch {
        _ => true
      },
    )
  }
  @execution.validate_as(
    ModelError("sdk.division_by_zero"),
    int,
    [],
    output=true,
  )
  assert_true(
    try {
      @execution.validate_as(ModelError("unexpected"), int, [], output=true)
      false
    } catch {
      _ => true
    },
  )
}

///|
test "exact comparison normalizes Decimal and record order while approximate Float is explicit" {
  assert_true(
    @execution.compare(
      Decimal(@bigint.BigInt::from_int(1250), -2),
      Decimal(@bigint.BigInt::from_int(125), -1),
    ),
  )
  assert_true(
    @execution.compare(
      Record([("a", Unit), ("b", Boolean(false))]),
      Record([("b", Boolean(false)), ("a", Unit)]),
    ),
  )
  let first : @execution.Value = Float64(1.0.reinterpret_as_uint64())
  let next : @execution.Value = Float64(1.00000001.reinterpret_as_uint64())
  assert_false(@execution.compare(first, next))
  assert_true(
    @execution.compare(first, next, policy=Approximate(0.000001, 0.0)),
  )
  assert_false(
    @execution.compare(
      Float64(0UL),
      Float64(0x8000000000000000UL),
      policy=Approximate(1.0, 1.0),
    ),
  )
  assert_false(
    @execution.compare(
      Float64(0x7ff8000000000042UL),
      Float64(0x7ff8000000000043UL),
      policy=Approximate(1.0, 1.0),
    ),
  )
  assert_true(
    @execution.compare(
      Float64(0x7ff8000000000042UL),
      Float64(0x7ff8000000000042UL),
    ),
  )
  assert_false(
    @execution.compare(Outcome(Err(Unit)), ModelError("sdk.division_by_zero")),
  )
  assert_true(
    try {
      ignore(@execution.compare(first, next, policy=Approximate(-1.0, 0.0)))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "rich projections reject nested duplicate fields invalid units bits and decimal precision" {
  for
    payload in [
      "{\"type\":\"text\",\"units\":[65536]}", "{\"type\":\"float64\",\"bits\":\"18446744073709551616\"}",
      "{\"type\":\"float64\",\"bits\":\"-1\"}", "{\"type\":\"decimal\",\"coefficient\":\"1\",\"exponent\":-33}",
      "{\"type\":\"maybe\",\"case\":\"nothing\",\"value\":{\"type\":\"unit\"}}",
      "{\"type\":\"list\",\"items\":[{\"type\":\"bool\",\"value\":true,\"value\":false}]}",
      "{\"type\":\"record\",\"fields\":[{\"name\":\"a\",\"value\":{\"type\":\"unit\"}},{\"name\":\"a\",\"value\":{\"type\":\"unit\"}}]}",
    ] {
    let source = "{\"profile\":\"morphir-invocations-v1\",\"calls\":[{\"id\":\"x\",\"entry\":\"e\",\"arguments\":[" +
      payload +
      "]}]}"
    assert_true(
      try {
        ignore(@execution.Suite::decode(@utf8.encode(source), "json"))
        false
      } catch {
        _ => true
      },
    )
  }
  let nested = "{type:\"list\",items:[".repeat(66) +
    "{type:\"unit\"}" +
    "]}".repeat(66)
  assert_true(
    try {
      ignore(
        @execution.Value::from_ion(
          @text.read_ion(("morphir_value::" + nested)[:]),
        ),
      )
      false
    } catch {
      _ => true
    },
  )
}

///|
test "unknown Ion extensions preserve annotations and native types in explicit projections" {
  let metadata = @text.read_ion(
    "audit::future::{number:amount::12345678901234567890.125,timestamp:2026-10-01T00:00:00Z,blob:{{AAEC}},symbol:future::token}"[:],
  )
  let bytes = @binary.write_binary_value(metadata)
  let suite : @execution.Suite = {
    extensions: Some(bytes),
    calls: [{ id: "a", entry: "e", arguments: [Unit], }],
  }
  for format in ["ion-text", "ion-binary", "json"] {
    let decoded = @execution.Suite::decode(suite.encode(format), format)
    assert_true(decoded.extension_value().equals(metadata))
    assert_eq(decoded.calls, suite.calls)
  }
}
