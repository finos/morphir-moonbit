///|
test "payload capture is separate opt in and redacts before sink delivery" {
  let values : Array[Json] = []
  let seen = Ref(0)
  let call : @execution.Call = {
    id: "call",
    entry: "pricing:quotes#total",
    arguments: [Boolean(false)],
  }
  let policy : @observability.PayloadCapture = {
    enabled: false,
    redact: fn(_, _) {
      seen.val += 1
      Some(Json::string("redacted"))
    },
    try_record: fn(value) {
      values.push(value)
      @observability.Accepted
    },
  }
  assert_true(policy.record(call, Unit) is Filtered)
  assert_eq(seen.val, 0)
  assert_true({ ..policy, enabled: true, }.record(call, Unit) is Accepted)
  assert_eq(seen.val, 2)
  assert_eq(values.length(), 1)
  assert_eq(values[0], {
    "profile": "morphir-redacted-payload-v1",
    "entry": "pricing:quotes#total",
    "call_id": "call",
    "arguments": ["redacted"],
    "result": "redacted",
  })
  let too_large : @observability.PayloadCapture = {
    ..policy,
    enabled: true,
    redact: fn(_, _) { Some(Json::string("x".repeat(16385))) },
  }
  assert_true(too_large.record(call, Unit) is Dropped)
  let unavailable : @observability.PayloadCapture = {
    ..policy,
    enabled: true,
    redact: fn(_, _) raise { raise Failure("redaction unavailable") },
  }
  assert_true(unavailable.record(call, Unit) is Unavailable)
  assert_eq(values.length(), 1)
}

///|
test "redactors cannot mutate caller arguments or outcomes through shared containers" {
  let input : @execution.Value = Text([65])
  let output : @execution.Value = Text([66])
  let call : @execution.Call = { id: "call", entry: "e", arguments: [input], }
  let capture : @observability.PayloadCapture = {
    enabled: true,
    redact: fn(_, value) {
      if value is Text(units) {
        units[0] = 0
      }
      None
    },
    try_record: fn(_) { @observability.Accepted },
  }
  assert_true(capture.record(call, output) is Accepted)
  assert_eq(input.to_json(), { "type": "text", "units": [65] })
  assert_eq(output.to_json(), { "type": "text", "units": [66] })
}
