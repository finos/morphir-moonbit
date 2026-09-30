///|
test "project languages resolve scripts without reading sources or requiring compilers" {
  let files = Map::from_array([
    (
      "morphir.toml", "[workspace]\nmembers=['a','b']\n[frontend]\nlanguage='elm'\n[pipeline]\nbackend='scala'",
    ),
    ("a/morphir.toml", "[project]\nname='A'"),
    ("b/morphir.toml", "[project]\nname='B'\n[frontend]\nlanguage='moonbit'"),
    ("morphir.config.scm", "(pipeline (backend \"scheme\"))"),
    (
      "b/morphir.config.scm", "(pipeline (frontend \"ir-json\") (backend \"ir-json\"))",
    ),
  ])
  let workspace = @workspace.discover({ files, directories: ["", "a", "b"], })
  let reads : Array[String] = []
  let memory = @engine.Host::memory(files)
  let host = {
    ..memory,
    read: fn(path) raise {
      reads.push(path)
      (memory.read)(path)
    },
    list: fn(_) raise {
      raise @configuration.Invalid("Sources must not be enumerated")
    },
  }
  let engine = @engine.Engine::new()
  let projects = engine.list_projects(host, workspace)
  assert_eq(projects.length(), 2)
  assert_eq(projects[0].frontend, Some("elm"))
  assert_eq(projects[0].target, Some("scheme"))
  assert_eq(projects[1].frontend, Some("ir-json"))
  assert_eq(projects[1].target, Some("ir-json"))
  assert_true(projects.all(p => p.error is None))
  assert_eq(reads, [
    "morphir.config.scm", "morphir.config.scm", "b/morphir.config.scm",
  ])
  let overridden = engine.list_projects(
    host,
    workspace,
    script="(pipeline (backend \"javascript\"))",
  )
  assert_true(overridden.all(p => p.target == Some("javascript")))
}

///|
test "project listing retains valid projects beside configuration errors" {
  let files = Map::from_array([
    ("morphir.toml", "[workspace]\nmembers=['a','b']"),
    ("a/morphir.toml", "[project]\nname='A'"),
    ("b/morphir.toml", "[project]\nname='B'"),
    ("b/morphir.config.scm", "(pipeline (frontend 42))"),
  ])
  let workspace = @workspace.discover({ files, directories: ["", "a", "b"], })
  let projects = @engine.Engine::new().list_projects(
    @engine.Host::memory(files),
    workspace,
  )
  assert_eq(projects[0].frontend, Some("scheme"))
  assert_eq(projects[0].target, Some("ir-json"))
  assert_eq(projects[1].frontend, None)
  assert_true(projects[1].error is Some(_))
}
