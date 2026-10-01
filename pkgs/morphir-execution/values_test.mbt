///|
test "Ion and explicit JSON preserve large integers bool and unit" {
  let suite = @execution.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      {
        "id": "one",
        "entry": "calls:main#subtract",
        "arguments": [
          { "type": "int", "value": "123456789012345678901234567890" },
          { "type": "bool", "value": false },
          { "type": "unit" },
        ],
      },
    ],
  })
  for format in ["ion-text", "ion-binary", "json"] {
    assert_eq(@execution.Suite::decode(suite.encode(format), format), suite)
  }
}

///|
test "invalid suite versions identities and numeric projections fail" {
  for
    source in [
      "{\"profile\":\"other\",\"calls\":[]}", "{\"profile\":\"morphir-invocations-v1\",\"calls\":[]}",
      "{\"profile\":\"morphir-invocations-v1\",\"profile\":\"morphir-invocations-v1\",\"calls\":[]}",
      "{\"profile\":\"morphir-invocations-v1\",\"calls\":[{\"id\":\"x\",\"entry\":\"e\",\"arguments\":[{\"type\":\"int\",\"value\":9007199254740993}]}]}",
    ] {
    let rejected = try {
      ignore(@execution.Suite::decode(@utf8.encode(source), "json"))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "duplicate call identities and annotated scalar values are refused" {
  let rejected = try {
    ignore(
      @execution.Suite::decode(
        @utf8.encode(
          "{profile:\"morphir-invocations-v1\",calls:[{id:\"a\",entry:\"e\",arguments:[]},{id:\"a\",entry:\"e\",arguments:[]}]}",
        ),
        "ion-text",
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let annotated = try {
    ignore(
      @execution.Suite::decode(
        @utf8.encode(
          "{profile:\"morphir-invocations-v1\",calls:[{id:\"a\",entry:\"e\",arguments:[secret::1]}]}",
        ),
        "ion-text",
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(annotated)
}
