///|
#cfg(target="native")
test "a failed compile replacement restores the bytes and leaves a tombstone" {
  if @platform.system_type() == "windows" {
    return
  }
  let root = @platform.temporary()
  defer dispose_build_tree(root)
  let destination = "out/compile.dest"
  let options : CompileRecordOptions = {
    explicit_selection: false,
    tree_product: Some("model"),
  }
  let publisher = ContentPublisher::filesystem(
    root,
    "out",
    compile_record=options,
  )
  let publish = (publisher.begin)([destination])
  (publish.stage)({
    path: destination + "/model/manifest.json",
    content: @data.Text("fixture"),
    format: "morphir-json",
    source: "fixture",
  })
  (publish.commit)(destination)
  (publish.abort)()
  let record_path = root + "/out/compile.json"
  let record = @wire.parse_bounded(@platform.read(record_path))
  let fields = @wire.object(record)
  fields["installed"] = { "/previous/install": ["manifest.json"] }
  @platform.write(record_path, record.stringify())

  let fail_publish = filesystem_content_publisher(
    root,
    "out",
    (source, destination) => {
      if source.contains("/.morphir-publish.lock/stage/") {
        raise @platform.IOError("fixture.staged_rename_failed")
      }
      @platform.rename(source, destination)
    },
    compile_record={ explicit_selection: false, tree_product: None, },
  )
  let publication = (fail_publish.begin)([destination])
  (publication.stage)({
    path: destination + "/replacement.json",
    content: @data.Text("replacement"),
    format: "morphir-json",
    source: "fixture",
  })
  let failure = try {
    (publication.commit)(destination)
    ""
  } catch {
    error => error_message(error)
  }
  (publication.abort)()
  assert_eq(failure, "fixture.staged_rename_failed")
  assert_eq(
    @platform.read(root + "/" + destination + "/model/manifest.json"),
    "fixture",
  )
  assert_eq(@platform.kind(root + "/" + destination + "/replacement.json"), 0)
  assert_eq(@platform.kind(root + "/out/.morphir-publish.lock"), 0)
  let tombstone = @wire.parse_bounded(@platform.read(record_path))
  assert_eq(@wire.field(tombstone, "tombstone"), Json::boolean(true))
  assert_eq(@wire.field(tombstone, "completedAt"), fields["completedAt"])
  assert_eq(@wire.field(tombstone, "installed"), fields["installed"])
  assert_eq(@wire.field(tombstone, "value"), Json::array([]))
  assert_eq(@wire.optional(tombstone, "ir"), None)
  let out = @platform.BoundedDirectory::open(root + "/out")
  defer out.close()
  let lease = out.try_task_lease("compile.lock", exclusive=true).unwrap()
  lease.close()
}
