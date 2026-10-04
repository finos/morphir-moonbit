///|
fn ion(value : String) -> @ion.IonValue raise {
  @text.read_ion(value[:])
}

///|
fn rejected(value : String, destination : @projection.Destination) -> Bool {
  try {
    ignore(@projection.project(ion(value), destination))
    false
  } catch {
    @projection.Invalid(_) => true
    _ => false
  }
}

///|
test "numeric bounds differ for JSON and OTLP without narrowing" {
  let safe = @projection.project(ion("9007199254740991"), @projection.JSON)
  assert_eq(safe.value, Some(Json::number(9007199254740991.0)))
  assert_true(rejected("9007199254740993", @projection.JSON))
  assert_eq(
    @projection.project(ion("9007199254740993"), @projection.OTLP).value,
    Some({ "intValue": "9007199254740993" }),
  )
  assert_eq(
    @projection.project(ion("-9223372036854775808"), @projection.OTLP).value,
    Some({ "intValue": "-9223372036854775808" }),
  )
  assert_true(rejected("9223372036854775808", @projection.OTLP))
  assert_true(rejected("-9223372036854775809", @projection.OTLP))
}

///|
test "rich values require a policy and envelopes preserve exact Ion bytes" {
  for
    source in [
      "12345678901234567890123456789012345d-32", "audit::{{AAEC/w==}}", "audit::null.int",
      "[1,2d-1]", "(foo 1)", "2000-01-01T", "symbol", "-0e0", "nan", "+inf", "{a:1,a:2}",
    ] {
    let value = ion(source)
    for destination in [@projection.JSON, @projection.OTLP] {
      assert_true(rejected(source, destination))
      let dropped = @projection.project(
        value,
        destination,
        policy=@projection.Drop,
      )
      assert_eq(dropped.value, None)
      assert_eq(dropped.dropped, 1)
      assert_eq(dropped.lossy, 1)
      assert_eq(dropped.encoded, 0)
      let encoded = @projection.project(
        value,
        destination,
        policy=@projection.Envelope,
      )
      assert_eq(encoded.lossy, 0)
      assert_eq(encoded.dropped, 0)
      assert_eq(encoded.encoded, 1)
      guard encoded.value is Some(Object(fields)) else { abort("envelope") }
      let data = if destination is @projection.JSON {
        fields["data"]
      } else {
        guard fields["kvlistValue"] is Object(kv) &&
          kv["values"] is Array(items) &&
          items[2] is Object(item) &&
          item["value"] is Object(bytes) else {
          abort("OTLP envelope")
        }
        bytes["bytesValue"]
      }
      guard data is String(text) else { abort("binary string") }
      let bytes = @base64.decode(text[:])
      let restored = @binary.read_binary_value(bytes[:])
      assert_eq(@binary.write_binary([restored]), @binary.write_binary([value]))
    }
  }
}

///|
test "binary OTLP uses bytesValue and JSON requires explicit preservation" {
  let result = @projection.project(ion("{{AAEC/w==}}"), @projection.OTLP)
  assert_eq(result.value, Some({ "bytesValue": "AAEC/w==" }))
  assert_eq(result.lossy, 0)
  assert_eq(result.encoded, 0)
  assert_true(rejected("{{AAEC/w==}}", @projection.JSON))
}

///|
test "unsupported child keeps precise path and never shifts list indexes" {
  let result = @projection.project(
    ion("{\"a/b~c\":[1,2d-1,3]}"),
    @projection.JSON,
    policy=@projection.Drop,
  )
  assert_eq(result.value, None)
  assert_eq(result.issues.length(), 1)
  assert_eq(result.issues[0].path, "/a~1b~0c/1")
  assert_eq(result.issues[0].reason, "exact_decimal")
  let result = @projection.project(
    ion("{ok:[true,\"value\",3]}"),
    @projection.OTLP,
  )
  assert_eq(
    result.value,
    Some({
      "kvlistValue": {
        "values": [
          {
            "key": "ok",
            "value": {
              "arrayValue": {
                "values": [
                  { "boolValue": true },
                  { "stringValue": "value" },
                  { "intValue": "3" },
                ],
              },
            },
          },
        ],
      },
    }),
  )
}

///|
test "policy cannot bypass depth limits" {
  let mut value = @ion.IonValue::int(1)
  for _ in 0..<66 {
    value = @ion.IonValue::list([value])
  }
  for policy in [@projection.Reject, @projection.Drop, @projection.Envelope] {
    assert_true(
      try {
        ignore(@projection.project(value, @projection.JSON, policy~))
        false
      } catch {
        @projection.Invalid(code) => code == "projection.limit"
        _ => false
      },
    )
  }
}

///|
test "aggregate size limit cannot be bypassed with many bounded fields" {
  let mut text = "x"
  for _ in 0..<20 {
    text = text + text
  }
  let item = @ion.IonValue::string(text)
  let value = @ion.IonValue::list([item, item, item])
  for policy in [@projection.Reject, @projection.Drop, @projection.Envelope] {
    assert_true(
      try {
        ignore(@projection.project(value, @projection.JSON, policy~))
        false
      } catch {
        @projection.Invalid(code) => code == "projection.limit"
        _ => false
      },
    )
  }
}
