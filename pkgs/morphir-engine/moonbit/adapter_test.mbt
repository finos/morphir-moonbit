///|
fn files(
  backend? : String = "checkpoint",
  component? : Bool = false,
) -> Map[String, String] {
  Map::from_array([
    (
      "morphir.toml",
      "[project]\nname='Pricing'\nmodule_prefix='App'\n[frontend]\nlanguage='moonbit'\n[pipeline]\nbackend='" +
      backend +
      "'\nvalidation='source-only'\n" +
      (if component { "components=['json-identity']" } else { "" }),
    ),
    (
      "src/Main.mbt", "// λ😀\npub fn eligible(active : Bool, vip : Bool) -> Bool { active && !vip }",
    ),
  ])
}

///|
fn plan(
  engine : @engine.Engine,
  snapshot : Map[String, String],
) -> @engine.Plan raise {
  engine.plan(
    @engine.Host::memory(snapshot),
    @workspace.discover({ files: snapshot, directories: ["", "src"], }),
    @engine.Request::new(),
  )
}

///|
fn execute(
  engine : @engine.Engine,
  snapshot : Map[String, String],
) -> @engine.ContentReport raise {
  engine.execute_content(plan(engine, snapshot), fn(path, _) {
    @data.Text(snapshot[path])
  })
}

///|
test "adapter observation is lazy and leaves binary Ion checkpoints unchanged" {
  let snapshot = files(component=true)
  let plain = @engine.Engine::new()
  @adapter.register(plain)
  let expected = execute(plain, snapshot)
  let records : Array[@observe.Observation] = []
  let engine = @engine.Engine::new()
  let observer : @observe.Observer = {
    ..@observe.Observer::noop(),
    enabled: fn() { true },
    try_record: fn(record) {
      records.push(record)
      @observe.Accepted
    },
  }
  @adapter.register(engine, observer~)
  let planned = plan(engine, snapshot)
  assert_eq(
    planned.source_frontends()[0].profile,
    Some("moonbit-model-bool-v1"),
  )
  assert_true(records.is_empty())
  let actual = execute(engine, snapshot)
  assert_true(actual.successful())
  guard actual.artifacts[0].content is @data.Binary(a) else {
    fail("Expected Ion binary")
  }
  guard expected.artifacts[0].content is @data.Binary(b) else {
    fail("Expected Ion binary")
  }
  assert_eq(a, b)
  assert_eq(
    records.filter(r => r.signal == @observe.Succeeded).map(r => r.stage),
    [@observe.Parse, @observe.ProfileCheck, @observe.Lower, @observe.Frontend],
  )
}

///|
test "explicit MoonBit registration preserves Ion origins through a JSON component" {
  let engine = @engine.Engine::new()
  let unavailable = try {
    ignore(plan(engine, files()))
    false
  } catch {
    @config.Invalid(message) => {
      assert_true(message.contains("Unknown frontend: moonbit"))
      true
    }
    error => raise error
  }
  assert_true(unavailable)
  @adapter.register(engine)
  let baseline = execute(engine, files())
  let rewritten = execute(engine, files(component=true))
  assert_true(baseline.successful())
  assert_true(rewritten.successful())
  let registry = @data.Registry::new()
  let original = registry.decode("ion-binary", {
    unit_id: "Main",
    content: baseline.artifacts[0].content,
  })
  let processed = registry.decode("ion-binary", {
    unit_id: "Main",
    content: rewritten.artifacts[0].content,
  })
  assert_eq(original.metadata.length(), 2)
  for (before, after) in original.metadata.zip(processed.metadata) {
    assert_eq(before.node_id, after.node_id)
    assert_true(before.data.equals(after.data))
  }
  assert_true(processed.provenance[0].equals(original.provenance[0]))
  assert_eq(processed.provenance.length(), 1)
  let entry = @ir.FQName::parse("pricing:app/main#source-656c696769626c65")
  for
    (active, vip, expected) in [
      (false, false, false),
      (false, true, false),
      (true, false, true),
      (true, true, false),
    ] {
    guard @backend.run_file(processed.distribution, entry, [
        @scheme.Boolean(active),
        @scheme.Boolean(vip),
      ])
      is Boolean(actual) else {
      fail("Expected Boolean")
    }
    assert_eq(actual, expected)
  }
}

///|
test "generated library Ion retains the adapted frontend metadata and provenance" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let report = execute(engine, files(backend="moonbit", component=true))
  assert_true(report.successful())
  assert_eq(report.projects.length(), 1)
  let artifact = report.artifacts.filter(a => a.path.has_suffix("symbols.10n"))[0]
  guard artifact.content is @data.Binary(bytes) else {
    fail("Expected Ion bytes")
  }
  let symbols = @ion_binary.read_binary_value(bytes[:])
  guard symbols.kind() is @ion.Struct(fields) else {
    fail("Expected symbol record")
  }
  let by_name = Map([])
  for field in fields {
    by_name[field.name().text().unwrap()] = field.value()
  }
  guard by_name["metadata"].kind() is @ion.List(metadata) else {
    fail("Expected metadata")
  }
  guard by_name["source_provenance"].kind() is @ion.List(provenance) else {
    fail("Expected provenance")
  }
  assert_eq(metadata.length(), 2)
  assert_eq(provenance.length(), 1)
  assert_eq(
    provenance[0].annotations()[0].text(),
    Some("morphir_moonbit_frontend"),
  )
}

///|
test "MoonBit dry runs describe the parser without parsing malformed source" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = files()
  snapshot["src/Main.mbt"] = "pub fn broken("
  let planned = plan(engine, snapshot)
  let descriptor = planned.source_frontends()[0]
  assert_eq(descriptor.profile, Some("moonbit-model-bool-v1"))
  assert_eq(descriptor.dependencies["moonbitlang/parser"], "0.4.1")
  assert_eq(descriptor.unit_id, "Main")
  let report = engine.execute_content(planned, fn(path, _) {
    @data.Text(snapshot[path])
  })
  assert_eq(report.processed, 0)
  assert_eq(report.diagnostics[0].stage, "frontend")
  assert_true(
    report.diagnostics[0].message.has_prefix("moonbit_frontend.syntax:"),
  )
}

///|
test "MoonBit rejection and cancellation retain diagnostic codes and spans" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = files()
  snapshot["src/Main.mbt"] = "pub fn bad(x : @other.Bool) -> Bool { true }"
  let rejected = execute(engine, snapshot)
  assert_true(
    rejected.diagnostics[0].message.has_prefix(
      "moonbit_frontend.unsupported_type:",
    ),
  )
  assert_true(rejected.diagnostics[0].message.contains(" at 1:"))
  let snapshot = files()
  let mut polls = 0
  let cancelled = engine.execute_content(
    plan(engine, snapshot),
    fn(path, _) { @data.Text(snapshot[path]) },
    cancelled=fn() {
      polls += 1
      polls > 3
    },
  )
  assert_eq(cancelled.processed, 0)
  assert_true(cancelled.artifacts.is_empty())
  assert_true(
    cancelled.diagnostics[0].message.has_prefix("moonbit_frontend.cancelled:"),
  )
}

///|
test "multiple MoonBit source files produce independent logical units" {
  let engine = @engine.Engine::new()
  @adapter.register(engine)
  let snapshot = files()
  snapshot["src/nested/Other.mbt"] = "pub fn other(x : Bool) -> Bool { !x }"
  snapshot["src/ignored.json"] = "not a MoonBit model"
  let planned = plan(engine, snapshot)
  assert_eq(planned.source_frontends().map(f => f.unit_id), [
    "Main", "nested/Other",
  ])
  let report = engine.execute_content(planned, fn(path, _) {
    @data.Text(snapshot[path])
  })
  assert_eq(report.processed, 2)
  assert_eq(report.artifacts.length(), 2)
  let artifact = report.artifacts.filter(a => a.source == "src/nested/Other.mbt")[0]
  let unit = @data.Registry::new().decode("ion-binary", {
    unit_id: "nested/Other",
    content: artifact.content,
  })
  let entry = @ir.FQName::parse("pricing:app/nested/other#source-6f74686572")
  guard @backend.run_file(unit.distribution, entry, [@scheme.Boolean(false)])
    is Boolean(actual) else {
    fail("Expected Boolean")
  }
  assert_true(actual)
}
