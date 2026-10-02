///|
#cfg(any(target="js", target="native"))
test "failed restoration retains original publication cause and accepted backup" {
  let root = @platform.temporary()
  defer dispose_build_tree(root)
  @platform.mkdir(root + "/out")
  @platform.mkdir(root + "/out/task")
  @platform.write(root + "/out/task/old.mbt", "accepted source")
  let prior = @ion_binary.write_binary_value(
    @ion.IonValue::string("accepted evidence"),
  )
  @platform.write_bytes(root + "/out/task/verification.ionb", prior)
  let renames = Ref(0)
  let publisher = filesystem_content_publisher(root, "out", fn(a, b) raise {
    renames.val += 1
    match renames.val {
      2 => raise @platform.IOError("fixture.publish_failed")
      3 => raise @platform.IOError("fixture.restore_failed")
      _ => @platform.rename(a, b)
    }
  })
  let plan = @execution.plan(
    @data.IRUnit::new("test", @fixtures.invocation_library()),
    @protocol.Suite::from_json({
      "profile": "morphir-invocations-v1",
      "calls": [
        {
          "id": "subtract",
          "entry": "calls:main#subtract",
          "arguments": [
            { "type": "int", "value": "5" },
            { "type": "int", "value": "3" },
          ],
        },
      ],
    }),
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
  let result = verify_and_publish(
    [plan],
    provider,
    @execution.Evaluator::scheme(),
    publisher,
    "out/task",
  )
  assert_false(result.committed)
  assert_false(result.successful())
  assert_true(result.reports[0].successful())
  let error = result.publication_error.unwrap()
  assert_true(error.contains("fixture.publish_failed"))
  assert_true(error.contains("fixture.restore_failed"))
  assert_true(error.contains("Manual recovery required"))
  let lock = root + "/out/.morphir-publish.lock"
  assert_eq(@platform.kind(lock), 2)
  assert_eq(@platform.kind(root + "/out/task"), 0)
  assert_eq(@platform.read(lock + "/backup/task/old.mbt"), "accepted source")
  assert_eq(
    @platform.read_bytes(lock + "/backup/task/verification.ionb"),
    prior,
  )
  // A new invocation must not steal this lock or delete the only accepted copy.
  let retry = verify_and_publish(
    [plan],
    provider,
    @execution.Evaluator::scheme(),
    ContentPublisher::filesystem(root, "out"),
    "out/task",
  )
  assert_false(retry.successful())
  assert_eq(
    @platform.read_bytes(lock + "/backup/task/verification.ionb"),
    prior,
  )
}
