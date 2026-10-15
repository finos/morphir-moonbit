///|
test "process authority binds without acquiring and missing grants refuse publication" {
  let host = @host.Host::new(
    @host.Mount::memory(a_metadata_session_workspace(true)),
  )
  let engine = @engine.Engine::new()
  host.register_process_metadata_provider(engine, None, "/work", "/invocation")
  let snapshot = host.snapshot()
  let plan = engine.plan(
    snapshot.engine_host(),
    @workspace.discover(snapshot.tree),
    { ..@engine.Request::new(), all: true, },
  )
  let outputs = Map::from_array([("previous.txt", @data.Text("retain"))])
  let result = host.run_content(engine, plan, {
    ..@host.ContentPublisher::memory(outputs),
    begin: fn(_) raise { fail("ungranted metadata reached publication") },
  })
  assert_false(result.successful())
  assert_true(
    result.report.diagnostics.all(d => {
      d.message.contains("metadata.restore_host_grants_required")
    }),
  )
  assert_eq(outputs.length(), 1)
  assert_eq(outputs["previous.txt"], @data.Text("retain"))
}

///|
test "process deadlines validate without resource acquisition" {
  let host = @host.Host::new(@host.Mount::memory(Map([])))
  for timeout in [0, 6000, 600001] {
    let refused = try {
      host.register_process_metadata_provider(
        @engine.Engine::new(),
        None,
        "/work",
        "/invocation",
        timeout~,
      )
      false
    } catch {
      error => @host.error_message(error) == "metadata.restore_invalid_deadline"
    }
    assert_true(refused)
  }
}
