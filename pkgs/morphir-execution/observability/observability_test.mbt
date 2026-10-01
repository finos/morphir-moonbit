///|
test "disabled observers perform no clock id sink or formatting work" {
  let calls = Ref(0)
  let observer : @observability.Observer = {
    enabled: fn() { false },
    try_record: fn(_) {
      calls.val += 1
      @observability.Accepted
    },
    monotonic: fn() {
      calls.val += 1
      0.0
    },
    wall: fn() {
      calls.val += 1
      0.0
    },
    next_id: fn() {
      calls.val += 1
      "id"
    },
    run_id: "run",
    sequence: Ref(0),
  }
  assert_eq(observer.scope().observe(@observability.Invoke, fn(_) { 42 }), 42)
  assert_eq(calls.val, 0)
}

///|
test "nested failure retains parentage and ends each scope once" {
  let records : Array[@observability.Observation] = []
  let sequence = Ref(0)
  let time = Ref(0.0)
  let observer : @observability.Observer = {
    enabled: fn() { true },
    try_record: fn(r) {
      records.push(r)
      @observability.Accepted
    },
    monotonic: fn() {
      time.val += 0.1
      time.val
    },
    wall: fn() { 1000.0 },
    next_id: fn() {
      sequence.val += 1
      sequence.val.to_string()
    },
    run_id: "run",
    sequence: Ref(0),
  }
  let rejected = try {
    observer
    .scope()
    .observe(@observability.Execute, fn(scope) raise {
      scope.observe(@observability.Build, fn(_) raise {
        raise @execution.Invalid("failure")
      })
    })
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(records.length(), 4)
  assert_true(records[0].signal is Started)
  assert_true(records[1].signal is Started)
  assert_true(records[2].signal is Failed)
  assert_true(records[3].signal is Failed)
  assert_eq(records[1].context.parent_id, records[0].context.span_id)
  assert_true(records[3].duration_seconds > 0.0)
}
