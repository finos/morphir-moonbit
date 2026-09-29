///|
test "project module prefixes and exposure are reflected in IR" {
  let files = Map::from_array([
    (
      "morphir.toml", "[project]\nname='Example'\nmodule_prefix='App'\nexposed_modules=[]",
    ),
    ("src/Main.scm", "42"),
  ])
  let host = @engine.Host::memory(files)
  let workspace = @workspace.discover({ files, directories: ["", "src"], })
  let engine = @engine.Engine::new()
  let plan = engine.plan(host, workspace, @engine.Request::new())
  let report = engine.execute(plan, host)
  assert_true(report.successful())
  let file = @ir_json.read(report.artifacts[0].content)
  guard file.distribution is Library(package_name, _, definition) else {
    fail("Expected library")
  }
  assert_eq(package_name.to_canonical(), "example")
  guard definition.modules.get(@ir.Path::parse("app/main")) is Some(module_def) else {
    fail("Expected prefixed module")
  }
  assert_eq(module_def.access, @ir.Access::Private)
}

///|
test "overlapping task destinations are rejected during planning" {
  let files = Map::from_array([
    (
      "morphir.toml", "[workspace]\nmembers=['compile.dest']\n[project]\nname='root'",
    ),
    ("compile.dest/morphir.toml", "[project]\nname='child'"),
  ])
  let host = @engine.Host::memory(files)
  let workspace = @workspace.discover({
    files,
    directories: ["", "compile.dest"],
  })
  let engine = @engine.Engine::new()
  let failed = try {
    ignore(
      engine.plan(host, workspace, { ..@engine.Request::new(), all: true, }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
