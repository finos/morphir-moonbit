///|
test "report preserves typed primary and cleanup errors with complete terminals" {
  let plan = @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    scalar_suite("5", "3"),
  )
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: fn() {
      {
        id: "lease",
        build: fn(_, _) raise { raise @protocol.Invalid("compile boom") },
        invoke: fn(_, _) { { values: [], evidence: Json::null(), } },
        dispose: fn() raise { raise @protocol.Invalid("cleanup boom") },
      }
    },
  }
  let report = @execution.run_report(plan, provider)
  assert_false(report.successful())
  assert_eq(report.terminals.length(), 1)
  assert_eq(report.terminals[0].status, "failed")
  let failure = report.failure.unwrap()
  assert_true(failure.cause is Some(@protocol.Invalid("compile boom")))
  assert_true(failure.cleanup is Some(@protocol.Invalid("cleanup boom")))
  let combined = try {
    ignore(@execution.run(plan, provider))
    false
  } catch {
    @execution.CleanupFailed(
      Some(@protocol.Invalid("compile boom")),
      @protocol.Invalid("cleanup boom")
    ) => true
    _ => false
  }
  assert_true(combined)
  assert_false(@execution.matrix_successful(["js"], [report]))
}

///|
test "cancelled calls remain required even with telemetry disabled" {
  let plan = @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    scalar_suite("5", "3"),
  )
  let acquired = Ref(false)
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: fn() raise {
      acquired.val = true
      raise @protocol.Invalid("unreachable")
    },
  }
  let report = @execution.run_report(plan, provider, cancelled=fn() { true })
  assert_false(acquired.val)
  assert_false(report.successful())
  assert_eq(report.terminals[0].status, "cancelled")
  assert_true(report.failure.unwrap().cancelled())
  assert_false(@execution.matrix_successful(["js", "native"], [report]))
}

///|
test "first structured mismatch retains typed values and escaped pointer" {
  let left = @protocol.Value::Record([
    ("a/b~c", @protocol.Value::Sequence([@protocol.Boolean(true)])),
  ])
  let right = @protocol.Value::Record([
    ("a/b~c", @protocol.Value::Sequence([@protocol.Boolean(false)])),
  ])
  assert_eq(@protocol.mismatch_path(left, right), Some("/a~1b~0c/0"))
  assert_eq(@protocol.mismatch_path(left, left), None)
}

///|
test "provider-owned outcome arrays cannot be changed by a later evaluator callback" {
  let value = @protocol.Value::from_json({ "type": "int", "value": "2" })
  let values = [value]
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: fn() {
      {
        id: "lease",
        build: fn(_, _) { Json::null() },
        invoke: fn(_, _) { { values, evidence: Json::null(), } },
        dispose: fn() { () },
      }
    },
  }
  let evaluator : @execution.Evaluator = {
    profile: "independent-test",
    evaluate: fn(_, _, _, _) {
      values[0] = @protocol.Boolean(false)
      value
    },
  }
  let plan = @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    scalar_suite("5", "3"),
  )
  let report = @execution.run_report(plan, provider, evaluator=Some(evaluator))
  assert_true(report.successful())
  assert_eq(report.calls[0].actual, value)
}
