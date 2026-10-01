///|
fn scalar_suite(a : String, b : String) -> @protocol.Suite raise {
  @protocol.Suite::from_json({
    "profile": "morphir-invocations-v1",
    "calls": [
      {
        "id": "subtract",
        "entry": "calls:main#subtract",
        "arguments": [
          { "type": "int", "value": a },
          { "type": "int", "value": b },
        ],
      },
    ],
  })
}

///|
test "custom provider uses portable contracts and live Scheme catches disagreement" {
  let unit = @data.IRUnit::new("test", @fixtures.invocation_library())
  let plan = @execution.plan(
    unit,
    scalar_suite("9007199254741035", "9007199254740993"),
  )
  let disposed = Ref(false)
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: () => {
      id: "memory-1",
      build: fn(_, _) { Json::null() },
      invoke: (_, _) => {
        values: [@protocol.Value::from_json({ "type": "int", "value": "41" })],
        evidence: Json::null(),
      },
      dispose: fn() { disposed.val = true },
    },
  }
  let report = @execution.run(
    plan,
    provider,
    evaluator=Some(@execution.Evaluator::scheme()),
  )
  assert_false(report.successful())
  assert_eq(
    report.calls[0].expected,
    Some(@protocol.Value::from_json({ "type": "int", "value": "42" })),
  )
  assert_true(disposed.val)
}

///|
test "driver source is independent of caller values" {
  let unit = @data.IRUnit::new("test", @fixtures.invocation_library())
  let first = @execution.plan(unit, scalar_suite("5", "3"))
  let second = @execution.plan(unit, scalar_suite("100", "1"))
  assert_eq(first.driver, second.driver)
  assert_eq(first.library.artifacts, second.library.artifacts)
}

///|
test "execution failure still disposes the session" {
  let plan = @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    scalar_suite("5", "3"),
  )
  let disposed = Ref(false)
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: () => {
      id: "memory-1",
      build: fn(_, _) raise { raise @protocol.Invalid("broken") },
      invoke: fn(_, _) { { values: [], evidence: Json::null(), } },
      dispose: fn() { disposed.val = true },
    },
  }
  let rejected = try {
    ignore(@execution.run(plan, provider))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_true(disposed.val)
}

///|
test "private entry wrong type and arity fail in planning" {
  let unit = @data.IRUnit::new("test", @fixtures.invocation_library())
  for
    (entry, arguments) in [
      ("calls:main#private", []),
      ("calls:main#subtract", []),
      ("calls:main#integer", [@protocol.Boolean(false)]),
    ] {
    let rejected = try {
      ignore(
        @execution.plan(unit, {
          extensions: None,
          calls: [{ id: "c", entry, arguments, }],
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "mutated call types are rejected before provider acquisition" {
  let plan = @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    scalar_suite("5", "3"),
  )
  plan.suite.calls[0].arguments[0] = @protocol.Boolean(false)
  let acquired = Ref(false)
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: () => {
      acquired.val = true
      raise @protocol.Invalid("unreachable")
    },
  }
  let rejected = try {
    ignore(@execution.run(plan, provider))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_false(acquired.val)
}

///|
test "wrong result type cannot succeed even without an evaluator" {
  let plan = @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    scalar_suite("5", "3"),
  )
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: () => {
      id: "memory",
      build: fn(_, _) { Json::null() },
      invoke: (_, _) => {
        values: [@protocol.Boolean(false)],
        evidence: Json::null(),
      },
      dispose: fn() { () },
    },
  }
  let rejected = try {
    ignore(@execution.run(plan, provider))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "planning requires an explicitly available LLVM capability" {
  let unit = @data.IRUnit::new("test", @fixtures.invocation_library())
  let suite = scalar_suite("5", "3")
  for target in ["llvm", "wasm", "unknown"] {
    let rejected = try {
      ignore(@execution.plan(unit, suite, target~))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let plan = @execution.plan(unit, suite, target="llvm", available_targets=[
    "llvm",
  ])
  assert_eq(plan.target, "llvm")
  for target in ["native", "wasm-gc"] {
    assert_eq(@execution.plan(unit, suite, target~).target, target)
  }
}
