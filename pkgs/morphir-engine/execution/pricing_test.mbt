///|
test "pricing manifest exposes typed boundaries and evaluator preserves domain values" {
  let unit = @data.IRUnit::new("pricing", @fixtures.pricing())
  let suite : @protocol.Suite = {
    extensions: None,
    calls: [{ id: "total", entry: "pricing:results#total", arguments: [], }],
  }
  let plan = @execution.plan(unit, suite) catch {
    @moonbit.Invalid(code, node, detail) =>
      fail(code + ": " + node + ": " + detail)
    error => raise error
  }
  let entry = plan.library.invocations.filter(e => {
      e.fqname == suite.calls[0].entry
    })[0]
  let result = (@execution.Evaluator::scheme().evaluate)(
    unit,
    suite.calls[0],
    entry.output,
    plan.library.invocation_types,
  )
  assert_eq(result.to_json(), {
    "type": "decimal",
    "coefficient": "375",
    "exponent": -1,
  })
}

///|
test "pricing evaluator decodes every manifest output" {
  let unit = @data.IRUnit::new("pricing", @fixtures.pricing())
  for name in ["quotes#sample", "quotes#approved", "results#failure"] {
    let call : @protocol.Call = {
      id: name,
      entry: "pricing:" + name,
      arguments: [],
    }
    let plan = @execution.plan(unit, { extensions: None, calls: [call], })
    let entry = plan.library.invocations.filter(e => e.fqname == call.entry)[0]
    ignore(
      (@execution.Evaluator::scheme().evaluate)(
        unit,
        call,
        entry.output,
        plan.library.invocation_types,
      ),
    ) catch {
      error => fail(name + ": " + error.to_string())
    }
  }
}

///|
test "instrumentation leaves rich plans semantic comparisons and required receipts unchanged" {
  let unit = @data.IRUnit::new("pricing", @fixtures.pricing())
  let suite : @protocol.Suite = {
    extensions: None,
    calls: [
      { id: "closure", entry: "pricing:results#mapped-sum", arguments: [], },
    ],
  }
  let first = @execution.plan(unit, suite)
  let second = @execution.plan(unit, suite)
  assert_eq(first.driver, second.driver)
  assert_eq(first.library.artifacts, second.library.artifacts)
  assert_eq(first.suite.encode("ion-binary"), second.suite.encode("ion-binary"))
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: () => {
      id: "memory",
      build: fn(_, _) { { "identity": "required-build" } },
      invoke: (_, _) => {
        values: [@protocol.Value::from_json({ "type": "int", "value": "36" })],
        evidence: { "identity": "required-invocation" },
      },
      dispose: fn() { () },
    },
  }
  let seen = Ref(0)
  let observer : @observe.Observer = {
    enabled: () => true,
    try_record: fn(_) {
      seen.val += 1
      @observe.Accepted
    },
    monotonic: () => 1.0,
    wall: () => 1.0,
    next_id: () => "1111111111111111",
    run_id: "observed",
    trace_id: "11111111111111111111111111111111",
    sequence: Ref(0),
  }
  let disabled = @execution.run(
    first,
    provider,
    evaluator=Some(@execution.Evaluator::scheme()),
  )
  let enabled = @execution.run(
    second,
    provider,
    evaluator=Some(@execution.Evaluator::scheme()),
    observer~,
  )
  assert_true(seen.val > 0)
  assert_eq(enabled.to_json(), disabled.to_json())
}

///|
test "unknown invocation exceptions remain failures and still clean up" {
  let unit = @data.IRUnit::new("pricing", @fixtures.pricing())
  let plan = @execution.plan(unit, {
    extensions: None,
    calls: [{ id: "call", entry: "pricing:results#total", arguments: [], }],
  })
  let disposed = Ref(false)
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: () => {
      id: "memory",
      build: fn(_, _) { Json::null() },
      invoke: fn(_, _) raise { raise Failure("unknown provider exception") },
      dispose: fn() { disposed.val = true },
    },
  }
  assert_true(
    try {
      ignore(@execution.run(plan, provider))
      false
    } catch {
      Failure(message) => message == "unknown provider exception"
      _ => false
    },
  )
  assert_true(disposed.val)
}
