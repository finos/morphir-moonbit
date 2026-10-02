///|
#cfg(any(target="js", target="native"))
test "filesystem verification faults preserve accepted sources and Ion evidence" {
  for
    fault in [
      "begin", "stage", "commit", "cancel", "stage-and-abort", "abort", "none",
    ] {
    let root = @platform.temporary()
    defer verification_remove(root)
    @platform.mkdir(root + "/out")
    @platform.mkdir(root + "/out/task")
    @platform.write(root + "/out/task/old.mbt", "accepted source")
    let prior = @ion_binary.write_binary_value(
      @ion.IonValue::string("accepted evidence"),
    )
    @platform.write_bytes(root + "/out/task/verification.ionb", prior)
    let cancelled = Ref(false)
    let disposed = Ref(false)
    let memory_provider : @execution.Provider = {
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
          dispose: fn() { disposed.val = true },
        }
      },
    }
    let filesystem = @host.ContentPublisher::filesystem(root, "out")
    let lock = root + "/out/.morphir-publish.lock"
    if fault == "begin" {
      @platform.mkdir(lock)
      @platform.write(lock + "/owner", "another publisher")
    }
    let publisher = {
      ..filesystem,
      begin: fn(destinations) raise {
        assert_true(disposed.val)
        let transaction = (filesystem.begin)(destinations)
        {
          stage: fn(artifact) raise {
            (transaction.stage)(artifact)
            if fault == "stage" || fault == "stage-and-abort" {
              raise @config.Invalid("fixture.stage_failed")
            }
            if fault == "cancel" {
              cancelled.val = true
            }
          },
          commit: fn(destination) raise {
            if fault == "commit" {
              // Remove the staged destination so the real second rename fails
              // after the accepted directory has moved into the backup.
              verification_remove(lock + "/stage/task")
            }
            (transaction.commit)(destination)
          },
          abort: fn() raise {
            if fault == "abort" || fault == "stage-and-abort" {
              raise @config.Invalid("fixture.abort_failed")
            }
            (transaction.abort)()
          },
        }
      },
    }
    let result = @host.verify_and_publish(
      [verification_plan("js")],
      memory_provider,
      @execution.Evaluator::scheme(),
      publisher,
      "out/task",
      cancelled=fn() { cancelled.val },
    )
    assert_true(result.reports[0].successful())
    assert_eq(result.committed, fault == "abort" || fault == "none")
    assert_eq(result.successful(), fault == "none")
    if result.committed {
      assert_eq(@platform.kind(root + "/out/task/old.mbt"), 0)
      assert_eq(@platform.kind(root + "/out/task/moon.mod"), 1)
      let receipt = @ion_binary.read_binary_value(
        @platform.read_bytes(root + "/out/task/verification.ionb")[:],
      )
      let fields = @protocol.fields(receipt, [
        "profile", "source_identity", "suite_identity", "required_targets", "reports",
      ])
      assert_eq(
        @protocol.string(@protocol.required(fields, "profile")),
        "morphir-verification-v1",
      )
    } else {
      assert_eq(@platform.read(root + "/out/task/old.mbt"), "accepted source")
      assert_eq(
        @platform.read_bytes(root + "/out/task/verification.ionb"),
        prior,
      )
      assert_eq(@platform.list(root + "/out/task").length(), 2)
    }
    if fault == "stage-and-abort" {
      let error = result.publication_error.unwrap()
      assert_true(error.contains("fixture.stage_failed"))
      assert_true(error.contains("fixture.abort_failed"))
    }
    let retained = ["begin", "stage-and-abort", "abort"].contains(fault)
    assert_eq(@platform.kind(lock), if retained { 2 } else { 0 })
    if fault == "begin" {
      assert_eq(@platform.read(lock + "/owner"), "another publisher")
    }
    if !retained {
      // A recovered failure must leave the next real transaction usable.
      let retry = @host.verify_and_publish(
        [verification_plan("js")],
        memory_provider,
        @execution.Evaluator::scheme(),
        filesystem,
        "out/task",
      )
      assert_true(retry.successful())
      assert_eq(@platform.kind(lock), 0)
    }
  }
}

///|
#cfg(any(target="js", target="native"))
fn verification_remove(path : String) -> Unit raise {
  match @platform.kind(path) {
    0 => ()
    2 => {
      for name in @platform.list(path) {
        verification_remove(path + "/" + name)
      }
      @platform.remove_dir(path)
    }
    _ => @platform.remove_file(path)
  }
}
