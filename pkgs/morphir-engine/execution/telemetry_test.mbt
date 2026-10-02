///|
fn lifecycle_observer(
  name : String,
  trace : String,
  records : Array[@observe.Observation],
) -> @observe.Observer {
  let next = Ref(0)
  let clock = Ref(0.0)
  {
    enabled: fn() { true },
    try_record: fn(record) {
      records.push(record)
      @observe.Dropped
    },
    monotonic: fn() {
      clock.val += 0.001
      clock.val
    },
    wall: fn() { 1000.0 + clock.val },
    next_id: fn() {
      next.val += 1
      let hex = next.val.to_string(radix=16)
      "0000000000000000"[:16 - hex.length()].to_owned() + hex
    },
    run_id: name,
    trace_id: trace,
    sequence: Ref(0),
  }
}

///|
test "every started execution stage terminates once even when all deliveries drop" {
  for
    fault in [
      "none", "build", "invoke", "evaluate", "cancel", "cleanup", "both",
    ] {
    let records : Array[@observe.Observation] = []
    let observer = lifecycle_observer(
      "run", "11111111111111111111111111111111", records,
    )
    let cancelled = Ref(false)
    let provider : @execution.Provider = {
      targets: ["js"],
      acquire: fn() {
        {
          id: "lease",
          build: fn(_, _) raise {
            if fault == "build" || fault == "both" {
              raise @protocol.Invalid("build")
            }
            Json::null()
          },
          invoke: fn(_, _) raise {
            if fault == "invoke" {
              raise @protocol.Invalid("invoke")
            }
            if fault == "cancel" {
              cancelled.val = true
            }
            {
              values: [
                @protocol.Value::from_json({ "type": "int", "value": "2" }),
              ],
              evidence: Json::null(),
            }
          },
          dispose: fn() raise {
            if fault == "cleanup" || fault == "both" {
              raise @protocol.Invalid("cleanup")
            }
          },
        }
      },
    }
    let scheme = @execution.Evaluator::scheme()
    let evaluator : @execution.Evaluator = {
      ..scheme,
      evaluate: fn(unit, call, output, customs) raise {
        if fault == "evaluate" {
          raise @protocol.Invalid("evaluate")
        }
        (scheme.evaluate)(unit, call, output, customs)
      },
    }
    let report = @execution.run_report(
      @execution.plan(
        @data.IRUnit::new("test", @fixtures.invocation_library()),
        scalar_suite("5", "3"),
      ),
      provider,
      evaluator=Some(evaluator),
      observer~,
      cancelled=fn() { cancelled.val },
    )
    assert_eq(report.successful(), fault == "none")
    assert_eq(report.terminals.length(), 1)
    let started = records.filter(r => r.signal is Started)
    let terminal = records.filter(r => {
      r.signal is Succeeded || r.signal is Failed || r.signal is Cancelled
    })
    assert_eq(started.length(), terminal.length())
    for record in started {
      let matches = terminal.filter(t => {
        t.context.span_id == record.context.span_id
      })
      assert_eq(matches.length(), 1)
      assert_eq(matches[0].context.run_id, record.context.run_id)
      assert_eq(matches[0].context.trace_id, record.context.trace_id)
      assert_eq(matches[0].context.parent_id, record.context.parent_id)
      assert_eq(matches[0].stage, record.stage)
      assert_true(matches[0].duration_seconds >= 0.0)
    }
    assert_true(records.all(r => r.context.run_id == "run"))
  }
}

///|
test "interleaved run scopes own independent clocks IDs sequences and parentage" {
  let outer_records : Array[@observe.Observation] = []
  let inner_records : Array[@observe.Observation] = []
  let outer = lifecycle_observer(
    "outer", "11111111111111111111111111111111", outer_records,
  )
  let inner = lifecycle_observer(
    "inner", "22222222222222222222222222222222", inner_records,
  )
  let plan = @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    scalar_suite("5", "3"),
  )
  let provider : @execution.Provider = {
    targets: ["js"],
    acquire: fn() {
      {
        id: "lease",
        build: fn(_, _) { Json::null() },
        invoke: fn(_, _) raise {
          {
            values: [
              @protocol.Value::from_json({ "type": "int", "value": "2" }),
            ],
            evidence: Json::null(),
          }
        },
        dispose: fn() { () },
      }
    },
  }
  let interleaved = {
    ..provider,
    acquire: fn() raise {
      let lease = (provider.acquire)()
      {
        ..lease,
        build: fn(plan, trace) raise {
          let nested = @execution.run_report(plan, provider, observer=inner)
          assert_true(nested.successful())
          (lease.build)(plan, trace)
        },
      }
    },
  }
  assert_true(
    @execution.run_report(plan, interleaved, observer=outer).successful(),
  )
  for (name, records) in [("outer", outer_records), ("inner", inner_records)] {
    assert_true(records.all(r => r.context.run_id == name))
    assert_eq(records[0].sequence, 1)
    assert_eq(records[0].context.parent_id, "")
    let root = records[0].context.span_id
    assert_true(
      records
      .filter(r => r.stage is Build || r.stage is Invoke || r.stage is Cleanup)
      .all(r => r.context.parent_id == root),
    )
    for i = 0; i < records.length(); i = i + 1 {
      assert_eq(records[i].sequence, i + 1)
    }
  }
  assert_true(outer_records.all(r => r.context.trace_id == outer.trace_id))
  assert_true(inner_records.all(r => r.context.trace_id == inner.trace_id))
}
