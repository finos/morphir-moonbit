///|
async fn publish_orders_product(
  root : String,
  module_path : String,
  fixture : String,
) -> Unit {
  let destination = "relocated/" + module_path + "/compile.dest"
  let publisher = @host.ContentPublisher::filesystem(root, "relocated", compile_record={
    explicit_selection: false,
    tree_product: Some("model"),
  })
  let publication = (publisher.begin)([destination])
  defer (publication.abort)()
  for
    path in [
      "manifest.json", "pkg/acme/orders/audit/module.json", "pkg/acme/orders/domain/module.json",
      "pkg/acme/orders/domain/order.type.json", "pkg/acme/orders/domain/order.value.json",
      "pkg/acme/orders/domain/total-in-_usd.value.json", "deps/morphir/_sdk/@/basics/module.json",
      "deps/morphir/_sdk/@/basics/int.type.json", "deps/morphir/_sdk/@/basics/add.value.json",
    ] {
    let bytes = @fs.read_file(fixture + "/" + path).binary()
    (publication.stage)({
      path: destination + "/model/" + path,
      source: path,
      content: @data.Binary(bytes),
      format: "morphir-json",
    })
  }
  (publication.commit)(destination)
}

///|
async fn wait_for_compile_lock(errors : @process.ReadFromProcess) -> String {
  for ;; {
    guard errors.read_until("\n") is Some(line) else {
      fail("native compile exited without waiting for the task lock")
    }
    if line.contains("waiting for another Morphir run to finish compile") {
      return line
    }
    println(line)
  }
}

///|
async test "native compile waits for the recorded producer capture and invalidates the replaced tree" {
  guard @env.get_env_var("MORPHIR_MEP_COMPILE_LEASE") == Some("1") else {
    return
  }
  let host = @fs.realpath(@env.get_env_var("MORPHIR_MEP_BOUNDED_HOST").unwrap())
  let digest = @identity.sha256(@fs.read_file(host).binary())
  assert_eq(
    digest,
    @env.get_env_var("MORPHIR_MEP_BOUNDED_HOST_SHA256").unwrap(),
  )
  let repository = @fs.realpath(
    @env.get_env_var("MORPHIR_MEP_BOUNDED_REPOSITORY").unwrap(),
  )
  let fixture = repository +
    "/apps/morphir-extension/acceptance/fixtures/acme-orders-v4/plain-json"
  let root = @fs.tmpdir(prefix="morphir-compile-lease-")
  defer @fs.rmdir(root, recursive=true)
  @fs.write_file(
    root + "/morphir.toml",
    "[workspace]\nmembers=['packages/*']\n",
  )
  let orders = "packages/orders"
  let sibling = "packages/other"
  for (module_path, name) in [(orders, "Orders"), (sibling, "Other")] {
    let member_root = root + "/" + module_path
    @fs.mkdir(member_root + "/src", recursive=true)
    @fs.write_file(
      member_root + "/morphir.toml",
      "[project]\nname='" + name + "'\nsource_directory='src'\n",
    )
    @fs.write_file(
      member_root + "/src/Main.mbt",
      "pub fn ready(active : Bool) -> Bool { !active }\n",
    )
    publish_orders_product(root, module_path, fixture)
  }
  let parent = root + "/relocated/" + orders
  let record = parent + "/compile.json"
  let other_record = root + "/relocated/" + sibling + "/compile.json"
  let before = @fs.read_file(record).binary()
  let other_before = @fs.read_file(other_record).binary()
  let record_json = @model_wire.parse_bounded(@utf8.decode(before[:]))
  assert_eq(@model_wire.field(record_json, "module"), Json::string(orders))
  assert_eq(@model_wire.field(record_json, "value"), ["model"])
  assert_eq(
    @model_wire.field(@model_wire.field(record_json, "ir"), "layout"),
    Json::string("document-tree"),
  )
  let task_dir = @platform.BoundedDirectory::open(parent)
  defer task_dir.close()
  let lock_before = task_dir.stamp(name="compile.lock")
  let source : TreeGenerationInput = CompileResult(record)
  let opened = source.open(() => ())
  defer (opened.release)()
  let command = [
    "compile", "--project", "Orders", "--output", "relocated", "--json",
  ]
  let environment = { "MORPHIR_HOME": root + "/home" }
  let root_directory = @platform.BoundedDirectory::open(root)
  defer root_directory.close()
  root_directory.mkdir("capture")
  let scratch = root_directory.child("capture")
  defer scratch.close()
  @async.with_timeout(10000, async fn() {
    @async.with_task_group(async fn(group) {
      let (errors, stderr) = @process.read_from_process()
      defer errors.close()
      let cancellation = root + "/cancel"
      let cancelled_log = root + "/cancelled.json"
      let cancelled = @process.spawn(
        group,
        host,
        command + ["--cancel-file", cancellation],
        cwd=root,
        extra_env=environment,
        stderr~,
        stdout=@process.redirect_to_file(cancelled_log),
      )
      println(wait_for_compile_lock(errors))
      assert_eq(cancelled.try_wait(), None)
      assert_false(@fs.exists(root + "/relocated/.morphir-publish.lock"))
      @fs.write_file(cancellation, "")
      assert_eq(cancelled.wait(), 130)
      let report = @fs.read_file(cancelled_log).json()
      assert_eq(
        @model_wire.field(@model_wire.field(report, "error"), "code"),
        Json::string("compile.cancelled"),
      )
      assert_eq(@fs.read_file(record).binary(), before)
      println(
        "compile cancelled while the capture lease remained held, exit 130",
      )
    })
    @async.with_task_group(async fn(group) {
      let (errors, stderr) = @process.read_from_process()
      defer errors.close()
      let writer_log = root + "/compile-result.json"
      let writer = @process.spawn(
        group,
        host,
        command,
        cwd=root,
        extra_env=environment,
        stderr~,
        stdout=@process.redirect_to_file(writer_log),
      )
      println(wait_for_compile_lock(errors))
      assert_eq(writer.try_wait(), None)
      assert_eq(@fs.read_file(record).binary(), before)
      let captured = capture_tree(
        opened.reopen,
        opened.directory,
        scratch,
        root_directory.stamp(),
        () => assert_eq(writer.try_wait(), None),
      )
      (opened.release)()
      assert_eq(writer.wait(), 0)
      let result = @fs.read_file(writer_log).json()
      assert_eq(@model_wire.field(result, "state"), Json::string("succeeded"))
      assert_true(@fs.exists(parent + "/compile.dest/Main.ionb"))
      assert_false(@fs.exists(parent + "/compile.dest/model"))
      assert_eq(task_dir.stamp(name="compile.lock"), lock_before)
      assert_eq(@fs.read_file(other_record).binary(), other_before)
      assert_true(
        @fs.exists(
          root + "/relocated/" + sibling + "/compile.dest/model/manifest.json",
        ),
      )
      let replacement = @fs.read_file(record).json()
      assert_eq(@model_wire.field(replacement, "value"), ["Main.ionb"])
      assert_eq(@model_wire.optional(replacement, "ir"), None)
      let refused = try {
        let stale = source.open(() => ())
        (stale.release)()
        false
      } catch {
        TreeSource(message) => message.contains("no IR descriptor")
        error => raise error
      }
      assert_true(refused)
      let view = @yaml.open_bounded_tree(
        captured.tree_source(() => ()),
        split_members_only=true,
      )
      let (_, manifest) = view.read_original_document(@yaml.ManifestArtifact)
      assert_eq(manifest, @fs.read_file(fixture + "/manifest.json").text())
      println(
        "compile replaced the product after capture, preserved the lock and sibling, and retired the stale descriptor",
      )
    })
  })
  let unrelated_output = "relocated/" + sibling + "/compile.dest"
  let legacy = @host.ContentPublisher::filesystem(root, "relocated")
  let replacement = (legacy.begin)([unrelated_output])
  (replacement.commit)(unrelated_output)
  (replacement.abort)()
  let tombstone = @fs.read_file(other_record).json()
  assert_eq(@model_wire.field(tombstone, "tombstone"), Json::boolean(true))
  let retired : TreeGenerationInput = CompileResult(other_record)
  let refused = try {
    let previous = retired.open(() => ())
    (previous.release)()
    false
  } catch {
    TreeSource(message) => message.contains("tombstone")
    error => raise error
  }
  assert_true(refused)
  println(
    "an unrecorded compile.dest replacement retired its old result with a reader-visible tombstone",
  )
}
