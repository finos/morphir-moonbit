///|
fn verification_plan(target : String) -> @execution.Plan raise {
  @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    {
      extensions: None,
      calls: [
        {
          id: "subtract",
          entry: "calls:main#subtract",
          arguments: [
            @protocol.Value::from_json({ "type": "int", "value": "5" }),
            @protocol.Value::from_json({ "type": "int", "value": "3" }),
          ],
        },
      ],
    },
    target~,
  )
}

///|
test "all verification work and cleanup precede atomic source and Ion publication" {
  let order = []
  let provider : @execution.Provider = {
    targets: ["js", "native"],
    acquire: fn() {
      order.push("acquire")
      {
        id: "lease",
        build: fn(_, _) {
          order.push("build")
          Json::null()
        },
        invoke: fn(_, _) raise {
          order.push("invoke")
          {
            values: [
              @protocol.Value::from_json({ "type": "int", "value": "2" }),
            ],
            evidence: Json::null(),
          }
        },
        dispose: fn() { order.push("dispose") },
      }
    },
  }
  let outputs = Map::from_array([("out/task/old", @data.Text("accepted"))])
  let memory = @host.ContentPublisher::memory(outputs)
  let publisher = {
    ..memory,
    begin: fn(destinations) raise {
      order.push("publish")
      (memory.begin)(destinations)
    },
  }
  let result = @host.verify_and_publish(
    [verification_plan("js"), verification_plan("native")],
    provider,
    @execution.Evaluator::scheme(),
    publisher,
    "out/task",
  )
  assert_true(result.committed)
  assert_eq(result.publication_error, None)
  assert_eq(order, [
    "acquire", "build", "invoke", "dispose", "acquire", "build", "invoke", "dispose",
    "publish",
  ])
  assert_false(outputs.contains("out/task/old"))
  guard outputs["out/task/verification.ionb"] is @data.Binary(bytes) else {
    fail("Ion receipt")
  }
  let receipt = @ion_binary.read_binary_value(bytes[:])
  let fields = @protocol.fields(receipt, [
    "profile", "source_identity", "suite_identity", "required_targets", "reports",
  ])
  assert_eq(
    @protocol.string(@protocol.required(fields, "profile")),
    "morphir-verification-v1",
  )
  assert_true(outputs.contains("out/task/moon.mod"))
}

///|
test "verification faults preserve accepted output without opening publisher" {
  for fault in ["compiler", "runner", "mismatch", "cleanup", "cancel", "source"] {
    let cancelled = Ref(false)
    let provider : @execution.Provider = {
      targets: ["js"],
      acquire: fn() {
        {
          id: "lease",
          build: fn(plan, _) raise {
            if fault == "compiler" {
              raise @config.Invalid("compiler failed")
            }
            if fault == "cancel" {
              cancelled.val = true
            }
            if fault == "source" {
              plan.library.artifacts[0] = {
                ..plan.library.artifacts[0],
                content: @moonbit.Text("changed"),
              }
            }
            Json::null()
          },
          invoke: fn(_, _) raise {
            if fault == "runner" {
              raise @config.Invalid("runtime trap")
            }
            {
              values: [
                @protocol.Value::from_json({
                  "type": "int",
                  "value": if fault == "mismatch" {
                    "3"
                  } else {
                    "2"
                  },
                }),
              ],
              evidence: Json::null(),
            }
          },
          dispose: fn() raise {
            if fault == "cleanup" {
              raise @config.Invalid("cleanup failed")
            }
          },
        }
      },
    }
    let outputs = Map::from_array([("out/task/old", @data.Text("accepted"))])
    let memory = @host.ContentPublisher::memory(outputs)
    let started = Ref(false)
    let publisher = {
      ..memory,
      begin: fn(destinations) raise {
        started.val = true
        (memory.begin)(destinations)
      },
    }
    let result = @host.verify_and_publish(
      [verification_plan("js")],
      provider,
      @execution.Evaluator::scheme(),
      publisher,
      "out/task",
      cancelled=fn() { cancelled.val },
    )
    assert_false(result.committed)
    assert_false(started.val)
    assert_eq(outputs.to_array(), [("out/task/old", @data.Text("accepted"))])
    assert_eq(result.reports[0].terminals.length(), 1)
  }
}
